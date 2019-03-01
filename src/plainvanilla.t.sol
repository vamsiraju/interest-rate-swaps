pragma solidity ^0.5.3;

import "ds-test/test.sol";

import "./plainvanilla.sol";

contract Tub {
    uint256 public _chi;
    function chi() public returns (uint256) { return _chi; }
    function setChi(uint256 chi_) public { _chi = chi_; }
}

contract PlainVanillaTest is DSTest {
    Tub tub;

    function setUp() public {
        tub = new Tub();
    }

    function test_set_chi() public {
        assertEq(tub.chi(), uint256(0));
        tub.setChi(123);
        assertEq(tub.chi(), 123);
    }
}
