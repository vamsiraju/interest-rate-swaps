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

    // receiver address => hash of the terms => reveiver's offer for these terms
    mapping(address => mapping(bytes32 => Offer)) public offers;

    struct Swap {
        address receiver;
        address payer;

        uint256 notionalAmt;
        uint256 fixedRate;
        uint256 maxRate;

        uint256 receiverLocked;
        uint256 payerLocked;

        uint256 startingRhi;
        uint256 endDate;
        bool settled;
    }

    mapping(uint => Swap) public swaps;
    uint nSwapId;

    event SwapCreated(address indexed receiver, address indexed payer, uint swapid);
    event SwapSettled(address indexed receiver, address indexed payer, uint swapid);

    mapping(address => uint256) public lockedBalance;

    constructor(TokenLike gem_, TubLike tub_) public {
        gem = gem_;
        tub = tub_;
    }

    function toRAY(uint256 wad) public pure returns(uint256 _ray) {
        _ray = mul(wad, 10 ** 9);
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

        swap.startingRhi = tub.rhi();
        swap.endDate = now + terms_.tenor;
        // swap.settled;

        // reserves locked for both parties
        swap.receiverLocked = sub(toRAY(notionalAmt_), rmul(toRAY(notionalAmt_), rpow(swap.maxRate, terms_.tenor))) / 10 ** 9;
        swap.payerLocked = sub(toRAY(notionalAmt_), rmul(toRAY(notionalAmt_), rpow(swap.fixedRate, terms_.tenor))) / 10 ** 9;

        require(gem.pull(receiver_, swap.receiverLocked));
        lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], swap.receiverLocked);

        require(gem.pull(msg.sender, swap.payerLocked));
        lockedBalance[msg.sender] = sub(lockedBalance[msg.sender], swap.payerLocked);

        nSwapId = nSwapId++;
    }

    // receiver or payer calls once after expiry to settle the swap 
    function settleSwap(uint256 swapid) public {
        Swap storage swap = swaps[swapid];
        
        require(!swap.settled);
        require(now >= swap.endDate);

        uint256 currentRhi = tub.rhi();
        uint256 accumulatedRhi = sub(currentRhi, startingRhi);
        
        // payer gets floating rate payments
        uint256 payerSettled = rmul(accumulatedRhi, toRAY(swap.notionalAmt)) / 10 ** 9;

        // cap max receiver payout to locked amt
        if(payerSettled > swap.receiverLocked) {
            payerSettled = swap.receiverLocked;
        }

        uint256 receiverRemaining = sub(swap.receiverLocked, payerSettled);

        receiverSettled = add(payerLocked, receiverRemaining);

        require(gem.push(receiver_, receiverSettled));
        lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], receiverSettled);

        require(gem.pull(msg.sender, payerSettled));
        lockedBalance[msg.sender] = sub(lockedBalance[msg.sender], payerSettled);

        swap.settled = true;
        emit SwapSettled(swap.receiver, swap.payer, swapid);
    }
}