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
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface TubLike {
    function rhi() external returns (uint256);
}

    // struct Offer {
    //     uint256 pot; // notional amount
    //     uint256 end; // offer end time
    // }

    // struct Swap {
    //     address lad;  // offer provider
    //     address gal;  // swap taker
    //     uint256 pot;  // notional
    //     uint256 tag;  // fixed rate
    //     uint256 cap;  // max payout
    //     uint256 rhi;  // starting rhi
    //     uint256 end;  // swap maturity timestamp
    //     bool settled; // has been settled
    // }

contract SwapEvents {
    event Settled(address indexed lad, address indexed gal);
    event NewSwap(
        address indexed lad, 
        address indexed gal, 
        uint256 indexed tag,
        uint256 cap,
        uint256 ttl,
        uint256 start,
        uint256 pot,
        uint256 rhi
    );
    event NewOffer(
        address indexed lad, 
        uint256 indexed tag, 
        uint256 cap,
        uint256 ttl,
        uint256 pot
    );
}

contract Swaps is DSMath, SwapEvents {
    TokenLike public gem; // payout token
    TubLike   public tub; // rate source

    mapping(bytes32 => uint256) public pots; // offerId => notional principal amount
    mapping(bytes32 => bool)   public swaps; // swapId  => isActive?

    constructor(address gem_, address tub_) public {
        gem = TokenLike(gem_);
        tub = TubLike(tub_);
    }

    // --- Provider Interface ---
    function offer(uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_) public {
        uint256 due = sub(rmul(toRAY(pot_), rpow(cap_, mul(ttl_, 1 days))) / 10 ** 9, pot_);
        require(gem.transferFrom(msg.sender, address(this), due), "swaps: token transfer failed");
        require(pot_ > 0.05 ether, "swaps: offer must have a pot of more than 0.05 gems");

        bytes32 offerId = keccak256(
            abi.encodePacked(msg.sender, tag_, cap_, mul(ttl_, 1 days))
        );
        require(pots[offerId] == 0, "swaps: pot not empty");
        pots[offerId] = pot_;
        emit NewOffer(msg.sender, tag_, cap_, mul(ttl_, 1 days), pot_);
    }
    // function tweak() {}

    // --- Taker Interface ---
    function take(
        address lad_, uint256 tag_, uint256 cap_, uint256 ttl_, uint256 pot_
    ) public {
        bytes32 offerId = keccak256(abi.encodePacked(lad_, tag_, cap_, ttl_));
        bytes32 swapId = keccak256(
            abi.encodePacked(lad_, msg.sender, tag_, cap_, ttl_, now, pot_, tub.rhi())
        );

        require(pots[offerId] > 0, "swaps: empty pot");
        require(pot_ > 0.05 ether,  "swaps: swap must have a pot of more than 0.05 gems");
        pots[offerId] = sub(pots[offerId], pot_);
        uint256 due = sub(rmul(toRAY(pot_), rpow(tag_, ttl_)) / 10 ** 9, pot_);
        require(gem.transferFrom(address(msg.sender), address(this), due), "swaps: token transfer failed");

        swaps[swapId] = true;
        emit NewSwap(lad_, msg.sender, tag_, cap_, ttl_, now, pot_, tub.rhi());
    }

    // --- Settlement ---
    function settle(
        address lad_, address gal_, uint256 pot_, uint256 tag_, 
        uint256 cap_, uint256 rhi_, uint256 start_, uint256 ttl_
    ) public {
        bytes32 swapId = keccak256(
            abi.encodePacked(lad_, gal_, tag_, cap_, ttl_, start_, pot_, rhi_)
        );
        
        require(swaps[swapId], "swaps: swap id must be of an active swap");
        require(now >= add(start_, ttl_), "swaps: swap must be past maturity");

        uint256 accruedInterest = mul(pot_, sub(tub.rhi(), rhi_));
        uint256 takerPool = sub(rmul(toRAY(pot_), rpow(tag_, ttl_)) / 10 ** 9, pot_);
        uint256 providerPool = sub(rmul(toRAY(pot_), rpow(cap_, ttl_)) / 10 ** 9, pot_);

        // if the accrued interest is more than what the taker pooled, the rate moved against the provider
        if (takerPool < accruedInterest) {
            // if the provider owes more than what they pooled, the taker gets whats there
            if (sub(accruedInterest, takerPool) > providerPool) {
                require(gem.transfer(gal_, add(takerPool, providerPool)), "swaps: token transfer failed");
            } else {
                // otherwise both parties get a payout, but the taker comes out ahead
                require(gem.transfer(gal_, accruedInterest), "swaps: token transfer failed");
                require(gem.transfer(lad_, sub(providerPool, sub(accruedInterest, takerPool))), "swaps: token transfer failed");
            }
        } else {
            // if the accrued interest is less than or equal to what the taker pooled, the provider comes out ahead
            require(gem.transfer(gal_, accruedInterest), "swaps: token transfer failed");
            require(gem.transfer(lad_, add(sub(takerPool, accruedInterest), providerPool)), "swaps: token transfer failed");
        }

        swaps[swapId] = false;
        emit Settled(lad_, gal_);
    }

    function toRAY(uint256 wad) internal pure returns(uint256 _ray) {
        _ray = mul(wad, 10 ** 9);
    }
}