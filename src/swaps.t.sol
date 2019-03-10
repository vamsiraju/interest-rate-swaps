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
    Swap   swap;
    constructor(address gem_, address swap_) public {
        gem = DSToken(gem_);
        swap = Swap(swap_);
    }
    function approve(address guy) public { 
        require(gem.approve(guy)); 
    }
    function createOffer(
        uint256 tag_, uint256 cap_, uint256 ttl_,
        uint256 pot_, uint256 end_
    ) public {
        swap.offer(tag_, cap_, ttl_, pot_, end_);
    }
}

contract SwapTest is DSTest {
    Tub     tub;
    DSToken gem;
    Swap   swap;

    Gal ava;
    Gal uma;

    function setUp() public {
        tub  = new Tub();
        gem  = new DSToken('Gem');


        swap = new Swap(address(gem), address(tub));
        ava  = new Gal(address(gem), address(swap));
        uma  = new Gal(address(gem), address(swap));

        gem.mint(200000 ether);
        gem.transfer(address(ava), 100000 ether);
        gem.transfer(address(ava), 100000 ether);
    }

    function test_set_rhi() public {
        assertEq(tub.rhi(), uint256(0));
        tub.setRhi(123);
        assertEq(tub.rhi(), 123);
    }

    function test_create_offer() public {
        ava.approve(address(swap));
        uint256 FIXED_RATE = 1000000001547125957863212449; // 5%
        uint256 SWAP_TTL = 12 weeks;
        uint256 NOTIONAL = 1000000; // 1 million 
        // max payout := interest on notional at a `fixed_rate` of 15% over `swap_ttl`
        uint256 MAX_PAYOUT = 3268725710033380431639; // 32,687
        uint256 OFFER_TTL = 3 days;
        ava.createOffer(FIXED_RATE, MAX_PAYOUT, SWAP_TTL, NOTIONAL, OFFER_TTL);

        (uint256 pot_, uint256 end_) = swap.offers(address(ava), keccak256(abi.encodePacked(FIXED_RATE, MAX_PAYOUT, SWAP_TTL)));
        assertEq(pot_, NOTIONAL);
        assertEq(end_, OFFER_TTL);
    }
}
