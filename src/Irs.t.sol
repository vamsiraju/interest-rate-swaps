pragma solidity ^0.5.3;

import "ds-test/test.sol";

import "./Irs.sol";

contract IrsTest is DSTest {
    Irs irs;

    function setUp() public {
        irs = new Irs();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
