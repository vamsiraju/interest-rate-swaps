pragma solidity ^0.5.3;

import "ds-math/math.sol";

contract TokenLike {
    function pull(address, uint256) public;
    function push(address, uint256) public;
}

contract TubLike {
    function rhi() public;
}


contract IRS is DSMath {
    uint256 public constant wait = 1 days;

    uint256 public term;
    uint256 public rate;
    uint256 public maxRate;
    uint256 public toStart;
    uint256 public startDate;
    uint256 public recieverDeposits;
    uint256 public totalPayerDeposits;
    uint256 public startingRhi;
    address public reciever;

    mapping(address => uint256) public payerDeposits;

    enum States {
        NULL,
        JOINABLE,
        STARTED
    }

    States public curerntState;
    TubLike public tub;
    TokenLike public gem;


    constructor(
        uint256 term_, uint256 rate_, uint256 maxRate_, 
        TokenLike gem_, TubLike tub_, address reciever_
    ) public {
        term = term_;
        rate = rate_; 
        gem = gem_;
        tub = tub_;
        maxRate = maxRate_;
        reciever = reciever_;
    }

    function init(uint256 recieverReserves) public {
        require(curerntState == states.NULL);
        gem.pull(reciever, recieverReserves);
        recieverDeposits = add(recieverDeposits, recieverReserves);
        toStart = add(wait, uint256(now));

        curerntState = states.JOINABLE;
    }

    function start() public {
        require(now >= toStart && curerntState == States.JOINABLE);

        // uint256 recieverReservesNeeded = mul(rmul(totalPayerDeposits, rpow(rate, term)), maxRate);
        // uint256 reservesToReturn = sub(recieverDeposits, recieverReservesNeeded);
        // gem.push(reciever, reservesToReturn);

        startDate = uint256(now);
        startingRhi = tub.rhi();
        curerntState = States.STARTED;
    }


    function join(uint256 notionalAmt) public {
        require(curerntState == States.JOINABLE);

        // payer joins
        uint256 depositsRequired = sub(mul(notionalAmt, 10 ** 9), rmul(mul(notionalAmt, 10 ** 9), rpow(rate, term))) / 10 ** 9;
        gem.pull(msg.sender, depositsRequired);
        totalPayerDeposits = add(totalPayerDeposits, deposits);
        payerDeposits[msg.sender] = add(depositsRequired, payerDeposits[msg.sender]);
    }

    function settle(address claimer) public {
        require(now >= startDate + term);
        if (claimer == reciever) {

        } else {

        }
    }

    function settleReciever() public {
        require(now >= startDate + term);
        uint256 currentRhi = tub.rhi();
        uint256 accumulatedRate = sub(currentRhi, startingRhi);
        uint256 realInterest = rmul(accumulatedRate, mul(totalPayerDeposits, 10 ** 9)) / 10 ** 9;
        uint256 fixedRateInteres = rmul(mul(totalPayerDeposits, 10 ** 9), rpow(rate, term)) / 10 ** 9;
        gem.push(reciever, owed);
    }
}


contract IRSFab {
    function newIRS(
        uint256 term_, uint256 rate_, uint256 maxRate, 
        TokenLike gem_, TubLike tub_
    ) public returns (IRS irs) {
        irs = new IRS(term_, rate_, maxRate, gem_, tub_, address(msg.sender));
    }
}
