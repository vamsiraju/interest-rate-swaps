pragma solidity ^0.5.3;

import "ds-test/test.sol";

import {DSToken} from "ds-token/token.sol";
import {Swap} from "./swap.sol";

contract Tub {
    uint256 public _rhi;
    function rhi() public view returns (uint256) { return _rhi; }
    function setRhi(uint256 rhi_) public { _rhi = rhi_; }
}

contract SwapTest is DSTest {
    Tub     tub;
    DSToken gem;

    function setUp() public {
        tub = new Tub();
        gem = new DSToken('Gem');
    }

    function test_set_rhi() public {
        assertEq(tub.rhi(), uint256(0));
        tub.setRhi(123);
        assertEq(tub.rhi(), 123);
    }
}
