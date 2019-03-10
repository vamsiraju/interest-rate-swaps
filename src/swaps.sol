/// swap.sol

// Copyright (C) 2019 Joshua Levine <jparklev@gmail.com>
// Copyright (C) 2019 Vamsi Alluri <hi@vamsiraju.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import "ds-math/math.sol";

interface TokenLike {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface TubLike {
    function rhi() external returns (uint256);
}

contract Swaps is DSMath {
    TokenLike public gem; // payout token
    TubLike   public tub; // rate source

    struct Offer {
        uint256 pot; // notional amount
        uint256 end; // offer end time
    }

    struct Swap {
        address lad;  // offer provider
        address gal;  // swap taker
        uint256 pot;  // notional
        uint256 tag;  // fixed rate
        uint256 cap;  // max payout
        uint256 rhi;  // starting rhi
        uint256 end;  // swap maturity timestamp
        bool settled; // has been settled
    }

    mapping(bytes32 => Offer) public offers;
    mapping(uint256 => Swap ) public swaps;
    uint256 nSwap;

    event Settled(address indexed receiver, address indexed payer, uint swapid);
    event NewSwap(address indexed receiver, address indexed payer, uint swapid);
    event NewOffer(
        address indexed lad, 
        uint256 indexed tag, 
        uint256 end, 
        uint256 cap,
        uint256 ttl,
        uint256 pot
    );

    constructor(address gem_, address tub_) public {
        gem = TokenLike(gem_);
        tub = TubLike(tub_);
    }

    // --- Provider Interface ---
    function offer(
        uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_, uint256 end_
    ) public {
        uint256 due = sub(rmul(toRAY(pot_), rpow(cap_, ttl_)) / 10 ** 9, pot_);
        require(gem.transferFrom(address(msg.sender), address(this), due));
        require(pot_ > 0.05 ether);

        uint256 life = mul(ttl_, 1 days);
        bytes32 offerId = keccak256(abi.encodePacked(address(msg.sender), tag_, cap_, life));
        offers[offerId].pot = pot_;
        offers[offerId].end = end_;
    }
    // function tweak() {}

    // --- Taker Interface ---
    function take(
        uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_, address lad_
    ) public {
        uint256 life = mul(ttl_, 1 days);
        bytes32 offerId = keccak256(abi.encodePacked(lad_, tag_, cap_, life));
        Offer storage offer = offers[offerId];
        Swap  storage swap  = swaps[nSwap];

        require(pot_ > 0.05 ether);
        require(now < offer.end);

        uint256 due = sub(rmul(toRAY(pot_), rpow(tag_, ttl_)) / 10 ** 9, pot_);
        require(gem.transferFrom(address(msg.sender), address(this), due));

        offer.pot = sub(offer.pot, pot_);

        swap.lad = lad_;
        swap.gal = address(msg.sender);
        swap.pot = pot_;
        swap.tag = tag_;
        swap.cap = cap_;

        swap.rhi = tub.rhi();
        swap.end = add(now, life);

        // emit NewSwap(lad_, msg.sender, pot, tag, cap, swap.rhi, swap.end, due, life);

        nSwap++;
    }


    // --- Settlement ---
    function settle(uint256 swapId) public {
        Swap storage swap = swaps[swapId];
        
        require(!swap.settled);
        require(now >= swap.end);

        uint256 accruedInterest = mul(swap.pot, rpow(sub(tub.rhi(), swap.rhi)));
        uint256 takerPool    = sub(rmul(toRAY(swap.pot), rpow(swap.tag, swap.ttl)) / 10 ** 9, swap.pot);
        uint256 providerPool = sub(rmul(toRAY(swap.pot), rpow(swap.cap, swap.ttl)) / 10 ** 9, swap.pot);

        // if the accrued interest is more than what the taker pooled, the rate moved against the provider
        if (takerPool < accruedInterest) {
            // if the provider owes more than what they pooled, the taker gets whats there
            if (accruedInterest - takerPool > providerPool) {
                require(gem.transferFrom(address(this), swap.gal, add(takerPool, providerPool)));
            } else {
                // both parties get a payout, the taker comes out ahead
                require(gem.transferFrom(address(this), swap.gal, accruedInterest));
                require(gem.transferFrom(address(this), swap.lad, sub(providerPool, sub(accruedInterest, takerPool))));
            }
        } else {
            // if the accrued interest is <= what the taker pooled, the provider comes out ahead
            require(gem.transferFrom(address(this), swap.gal, accruedInterest));
            require(gem.transferFrom(address(this), swap.lad, add(sub(takerPool, accruedInterest), providerPool));
        }

        swap.settled = true;

        // emit SwapSettled(swap.lad, swap.gal, swapId);
    }

    function toRAY(uint256 wad) internal pure returns(uint256 _ray) {
        _ray = mul(wad, 10 ** 9);
    }
}