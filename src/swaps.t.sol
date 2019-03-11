pragma solidity >=0.5.0;

import "ds-test/test.sol";
import "ds-math/math.sol";

import {DSToken} from "ds-token/token.sol";
import {Swaps} from "./swaps.sol";

contract Tub {
    uint256 public _rhi;
    function rhi() public view returns (uint256) { return _rhi; }
    function setRhi(uint256 rhi_) public { _rhi = rhi_; }
}

contract Hevm {
    function warp(uint256) public;
}

contract Gal {
    DSToken gem;
    Swaps swaps;
    constructor(address gem_, address swaps_) public {
        gem = DSToken(gem_);
        swaps = Swaps(swaps_);
    }
    function approve(address guy) public { 
        require(gem.approve(guy), "gal: token transfer failed"); 
    }
    function createOffer(uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_) public {
        swaps.offer(tag_, cap_, ttl_, pot_);
    }
    function takeOffer(address lad_, uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_) public {
        swaps.take(lad_, tag_, cap_, ttl_, pot_);
    }
    function settleSwap(
        address lad_, address gal_, uint256 pot_, uint256 tag_, 
        uint256 cap_, uint256 rhi_, uint256 start_, uint256 ttl_
    ) public {
        swaps.settle(lad_, gal_, pot_, tag_, cap_, rhi_, start_, ttl_);
    }
}

contract SwapTest is DSTest, DSMath {
    Tub     tub;
    DSToken gem;
    Swaps swaps;
    Hevm   hevm;

    Gal ava;
    Gal uma;

    function setUp() public {
        // HEVM cheat -> set the block timestamp
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        tub  = new Tub();
        gem  = new DSToken('Gem');

        swaps = new Swaps(address(gem), address(tub));
        ava   = new Gal(address(gem), address(swaps));
        uma   = new Gal(address(gem), address(swaps));

        gem.mint(200000 ether);
        gem.transfer(address(ava), 100000 ether);
        gem.transfer(address(uma), 100000 ether);
    }

    function test_set_rhi() public {
        assertEq(tub.rhi(), uint256(0));
        tub.setRhi(123);
        assertEq(tub.rhi(), 123);
    }

    function test_create_offer() public {
        ava.approve(address(swaps));
        assertEq(gem.balanceOf(address(ava)), 100000 ether);

        uint256 FIXED_RATE = 1000000001547125957863212449; // 5%
        // max payout := interest on notional at a fixed_rate of max_payout_rate 
        uint256 MAX_PAYOUT_RATE = 1000000004431822129783699001;
        uint256 SWAP_TTL = 84; // 84 days or 12 weeks
        uint256 NOTIONAL = 1000000 ether; // 1 million dai
        ava.createOffer(FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL, NOTIONAL);

        uint256 DUE = 32687257100333804314102; // 15% on notional over 12 weeks
        assertEq(gem.balanceOf(address(ava)), 100000 ether - DUE);
        bytes32 offerId = keccak256(
            abi.encodePacked(address(ava), FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL * 1 days)
        );
        uint256 pot = swaps.pots(offerId);
        assertEq(pot, NOTIONAL);
    }

    function test_take_offer() public {
        ava.approve(address(swaps));
        uma.approve(address(swaps));
        tub.setRhi(123);

        uint256 FIXED_RATE = 1000000001547125957863212449; // 5%
        uint256 MAX_PAYOUT_RATE = 1000000004431822129783699001; // 15%
        uint256 SWAP_TTL_IN_DAYS = 84;
        uint256 SWAP_TTL_IN_SECONDS = 12 weeks;
        uint256 NOTIONAL = 1000000 ether;
        ava.createOffer(FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL_IN_DAYS, NOTIONAL);

        uma.takeOffer(address(ava), FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL_IN_SECONDS, NOTIONAL);
    }

    function test_settlement() public {
        ava.approve(address(swaps)); // receiver
        uma.approve(address(swaps)); // payer

        uint256 STARTING_RHI = 10 ** 27;
        uint256 STARTING_TIME = now;
        tub.setRhi(STARTING_RHI);

        uint256 FIXED_RATE = 1000000001547125957863212449; // 5% 
        uint256 MAX_PAYOUT_RATE = 1000000004431822129783699001; // 15%
        uint256 SWAP_TTL_IN_DAYS = 84;
        uint256 SWAP_TTL_IN_SECONDS = 12 weeks;
        uint256 NOTIONAL = 1000000 ether;
        ava.createOffer(FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL_IN_DAYS, NOTIONAL);
        uma.takeOffer(address(ava), FIXED_RATE, MAX_PAYOUT_RATE, SWAP_TTL_IN_SECONDS, NOTIONAL);

        uint256 SIMULATED_RATE = 1000000000937303470807876290; // 3%
        uint256 RHI_12_WEEKS_3_PERCENT = rpow(SIMULATED_RATE, 12 weeks);
        tub.setRhi(RHI_12_WEEKS_3_PERCENT);
        hevm.warp(12 weeks);

        uma.settleSwap(
            address(ava), address(uma), NOTIONAL, FIXED_RATE, MAX_PAYOUT_RATE, 
            STARTING_RHI, STARTING_TIME, SWAP_TTL_IN_SECONDS
        );

        assertEq(gem.balanceOf(address(swaps)), 0);
        assertEq(gem.balanceOf(address(uma)), 95534067053380677175532);
        assertEq(gem.balanceOf(address(ava)), 104465932946619322824468);// ~ 44,660 gems profit
    }

    // TODO:
    // tweak
    // multiple partial offers
    // multiple swaps on one offer
    // rhi variations
    // payer profit, not max payout
    // payer profit, max payout 
}

