pragma solidity ^0.5.3;

import "ds-test/test.sol";

import "./vanilla-irs.sol";

contract Tub {
    uint256 public _chi;
    function chi() public returns (uint256) { return _chi; }
    function setChi(uint256 chi_) public { _chi = chi_; }
}

contract VanillaIRS is DSTest {
    Tub tub;

    function setUp() public {
        tub = new Tub();
    }
}
