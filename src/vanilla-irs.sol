pragma solidity ^0.5.3;

import "ds-math/math.sol";

contract TokenLike {
    function pull(address, uint256) public;
    function push(address, uint256) public;
}

contract TubLike {
    function rhi() public;
}

contract VanillaIRS is DSMath {
    TokenLike public gem;
    TubLike public tub;

    struct Terms {
        uint256 fixedRate;
        uint256 maxFloatingRate;
        uint256 tenor;
    }

    struct Offer {
        uint256 amt;
        uint256 expiry;
    }

    // mapping: receiver address => hash of the terms => reveiver's offer for these terms
    mapping(address => mapping(bytes32 => Offer)) public offers;

    struct Swap {
        address receiver;
        address payer;

        uint256 notionalAmt;
        uint256 fixedRate;
        uint256 maxRate;

        uint256 startRhi;
        uint256 settledRhi;
        uint256 settlementDate;
        bool    settled;
    }

    mapping(uint => Swap) public swaps;
    uint nSwapId;

    event SwapCreated(address indexed receiver, address indexed payer, uint swapid);

    mapping(address => uint256) public lockedBalance;

    constructor(TokenLike gem_, TubLike tub_) public {
        gem = gem_;
        tub = tub_;
    }

    // receivers can update their offers for terms anytime
    // balance is locked from receiver when a swap is created
    function updateOffer(Terms terms_, Offer offer) public {
        bytes32 termsId = keccak256(abi.encodePacked(terms_));
        offers[msg.sender][termsId] = offer;
    }

    function createSwap(address receiver_, Terms terms_, uint256 notionalAmt_) public {
        bytes32 termsId = keccak256(abi.encodePacked(terms_));
        Offer storage offer = offers[receiver_][termsId];
        Swap storage swap = swaps[nSwapId];
        
        require(now <= offer.expiry);
        offer.amt = sub(offer.amt, notionalAmt_);

        swap.receiver = receiver_;
        swap.payer = msg.sender;

        swap.notionalAmt = notionalAmt_;
        swap.fixedRate = terms_.fixedRate;
        swap.maxRate = terms_.maxFloatingRate;

        swap.startRhi = tub.rhi();
        swap.settledRhi = tub.rhi(); // can be left at 0 too?
        swap.settlementDate = now + terms_.tenor;
        // swap.settled;

        // calculate the amount of reserves to lock for both parties

        // use require when transferring funds

        nSwapId = nSwapId++;
    }

    // either receiver or payer has to individually settle each swap
    // settlement is done once after expiry in this implementation
    function settleSwap(uint256 swapid) public {
        Swap storage swap = swaps[swapid];
        
        require(!swap.settled);
        require(now >= swap.settlementDate);

        // calculate payout
        // transfer from locked reserves to both parties

        swap.settled = true;
    }
}