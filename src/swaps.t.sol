pragma solidity ^0.5.3;

import "ds-test/test.sol";

import {DSToken} from "ds-token/token.sol";
import {Swaps} from "./swaps.sol";

contract Tub {
    uint256 public _rhi;
    function rhi() public view returns (uint256) { return _rhi; }
    function setRhi(uint256 rhi_) public { _rhi = rhi_; }
}

contract Gal {
    DSToken gem;
    Swaps swaps;
    constructor(address gem_, address swaps_) public {
        gem = DSToken(gem_);
        swaps = Swaps(swaps_);
    }
    function approve(address guy) public { 
        require(gem.approve(guy)); 
    }
    function createOffer(uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_) public {
        swaps.offer(tag_, cap_, ttl_, pot_);
    }
    function takeOffer(address lad_, uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_) public {
        swaps.take(lad_, tag_, cap_, ttl_, pot_);
    }
}

contract SwapTest is DSTest {
    Tub     tub;
    DSToken gem;
    Swaps swaps;

    Gal ava;
    Gal uma;

    function setUp() public {
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
    // multiple partial offers
}
