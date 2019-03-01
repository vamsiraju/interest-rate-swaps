pragma solidity ^0.5.3;

import "ds-math/math.sol";

interface TokenLike {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface TubLike {
    function rhi() external returns (uint256);
}

contract PlainVanilla is DSMath {
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
    function updateOffer(
        uint256 fixedRate_,
        uint256 maxFloatingRate_,
        uint256 tenor_,
        uint256 amt_,
        uint256 expiry_
    ) 
    public 
    {
        bytes32 termsId = keccak256(abi.encodePacked(fixedRate_, maxFloatingRate_, tenor_));
        offers[msg.sender][termsId].amt = amt_;
        offers[msg.sender][termsId].amt = expiry_;
    }

    function createSwap(
        address receiver_, 
        uint256 fixedRate_,
        uint256 maxFloatingRate_,
        uint256 tenor_, 
        uint256 notionalAmt_
    ) 
    public 
    {
        bytes32 termsId = keccak256(abi.encodePacked(fixedRate_, maxFloatingRate_, tenor_));
        Offer storage offer = offers[receiver_][termsId];
        Swap storage swap = swaps[nSwapId];
        
        require(now <= offer.expiry);
        offer.amt = sub(offer.amt, notionalAmt_);

        swap.receiver = receiver_;
        swap.payer = msg.sender;

        swap.notionalAmt = notionalAmt_;
        swap.fixedRate = fixedRate_;
        swap.maxRate = maxFloatingRate_;

        swap.startingRhi = tub.rhi();
        swap.endDate = now + tenor_;
        // swap.settled;

        // reserves locked for both parties
        swap.receiverLocked = sub(toRAY(notionalAmt_), rmul(toRAY(notionalAmt_), rpow(swap.maxRate, tenor_))) / 10 ** 9;
        swap.payerLocked = sub(toRAY(notionalAmt_), rmul(toRAY(notionalAmt_), rpow(swap.fixedRate, tenor_))) / 10 ** 9;

        require(gem.transferFrom(receiver_, address(this), swap.receiverLocked));
        lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], swap.receiverLocked);

        require(gem.transferFrom(msg.sender, address(this), swap.payerLocked));
        lockedBalance[msg.sender] = sub(lockedBalance[msg.sender], swap.payerLocked);

        nSwapId = nSwapId++;
    }

    // receiver or payer calls once after expiry to settle the swap 
    function settleSwap(uint256 swapid) public {
        Swap storage swap = swaps[swapid];
        
        require(!swap.settled);
        require(now >= swap.endDate);

        uint256 currentRhi = tub.rhi();
        uint256 accumulatedRhi = sub(currentRhi, swap.startingRhi);
        
        // payer gets floating rate payments
        uint256 payerSettled = rmul(accumulatedRhi, toRAY(swap.notionalAmt)) / 10 ** 9;

        // cap max receiver payout to locked amt
        if(payerSettled > swap.receiverLocked) {
            payerSettled = swap.receiverLocked;
        }

        uint256 receiverRemaining = sub(swap.receiverLocked, payerSettled);
        uint256 receiverSettled = add(swap.payerLocked, receiverRemaining);

        require(gem.transfer(swap.receiver, receiverSettled));
        lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], receiverSettled);

        require(gem.transfer(swap.payer, payerSettled));
        lockedBalance[swap.payer] = sub(lockedBalance[swap.payer], payerSettled);

        swap.settled = true;
        emit SwapSettled(swap.receiver, swap.payer, swapid);
    }
}