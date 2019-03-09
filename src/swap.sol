pragma solidity >=0.5.0;

import "ds-math/math.sol";

interface TokenLike {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface TubLike {
    function rhi() external returns (uint256);
}

/**
 Plain Vanilla Interest Rate Swap
  * Tenor - total term of the swap
  * Receiver - pays stability fee rate capped at a max
  * Payer - cdp owner pays a fixed rate over the tenor
 */ 

contract Swap is DSMath {
    TokenLike public gem; // payout token
    TubLike   public tub; // rate source

    struct Offer {
        uint256 pot; // notional amount
        uint256 end; // offer lifetime
    }

    event Created();

    // receiver address => terms hash => reveiver's offer for these terms
    mapping(address => mapping(bytes32 => Offer)) public offers;
    mapping(address => uint256) deposits;

    struct Swap {
        address lad;
        address gal;
        uint256 pot;
        uint256 tag;
        uint256 cap;
        uint256 startingRhi;
        uint256 end;
        bool    settled;
    }

    mapping(uint => Swap) public swaps;
    uint256 nSwap;

    mapping(address => uint256) public lockedBalance;

    event SwapCreated(address indexed receiver, address indexed payer, uint swapid);
    event SwapSettled(address indexed receiver, address indexed payer, uint swapid);

    constructor(TokenLike gem_, TubLike tub_) public {
        gem = gem_;
        tub = tub_;
    }

    // --- Provider Interface ---
    function offer(
        uint256 tag_, uint256 cap_, uint256 ttl_,
        uint256 pot_, uint256 end_
    ) public {
        uint256 due = sub(rmul(toRAY(pot_), rpow(cap_, ttl_)) / 10 ** 9, pot_);
        require(gem.transferFrom(address(msg.sender), address(this), due));
        // deposits[msg.sender]
        bytes32 offerId = keccak256(abi.encodePacked(tag_, cap_, ttl_));
        offers[msg.sender][offerId].pot = pot_;
        offers[msg.sender][offerId].end = end_;
    }
    // function tweak() {}

    // --- Taker Interface ---
    function take(
        address lad_, uint256 tag_, uint256 cap_,
        uint256 ttl_, uint256 pot_
    ) public {
        bytes32 offerId = keccak256(abi.encodePacked(tag_, cap_, ttl_));
        Offer storage offer = offers[lad_][offerId];
        Swap  storage swap  = swaps[nSwap];

        require(now < offer.end);

        uint256 due = sub(pot_, rmul(toRAY(pot_), rpow(tag_, ttl_)) / 10 ** 9);
        require(gem.transferFrom(address(msg.sender), address(this), due));

        offer.pot = sub(offer.pot, pot_);

        swap.lad = lad_;
        swap.gal = msg.sender;

        swap.pot = pot_;
        swap.tag = tag_;
        swap.cap = cap_;

        swap.startingRhi = tub.rhi();
        swap.end = add(now, ttl_);


        // lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], swap.receiverLocked);
        // lockedBalance[msg.sender] = sub(lockedBalance[msg.sender], swap.payerLocked);

        nSwap++;


    }


    // --- Settlement ---
    function settle(uint256 swapid) public {
        Swap storage swap = swaps[swapid];
        
        require(!swap.settled);
        require(now >= swap.end);

        // uint256 accumulatedRhi = sub(tub.rhi(), swap.startingRhi);
        
        // // payer gets floating rate payments
        // uint256 payerSettled = rmul(accumulatedRhi, toRAY(swap.notionalAmt)) / 10 ** 9;

        // // cap max payout to receiver locked amt
        // if(payerSettled > swap.receiverLocked) {
        //     payerSettled = swap.receiverLocked;
        // }

        // uint256 receiverRemaining = sub(swap.receiverLocked, payerSettled);
        // uint256 receiverSettled = add(swap.payerLocked, receiverRemaining);

        // require(gem.transfer(swap.receiver, receiverSettled));
        // lockedBalance[swap.receiver] = sub(lockedBalance[swap.receiver], receiverSettled);

        // require(gem.transfer(swap.payer, payerSettled));
        // lockedBalance[swap.payer] = sub(lockedBalance[swap.payer], payerSettled);

        // swap.settled = true;
        // emit SwapSettled(swap.receiver, swap.payer, swapid);
    }

    function toRAY(uint256 wad) public pure returns(uint256 _ray) {
        _ray = mul(wad, 10 ** 9);
    }
}