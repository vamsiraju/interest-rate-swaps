/// swaps.sol

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

contract SwapEvents {
    event Settled(address indexed lad, address indexed gal);
    event NewSwap(
        address indexed lad, // receiver
        address indexed gal, // payer
        uint256 indexed tag, // swap rate
        uint256 cap,   // max payout rate
        uint256 ttl,   // time-to-maturity
        uint256 start, // starting timestamp
        uint256 pot,   // notional principal
        uint256 rhi    // rate accumulator value
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

    mapping(bytes32 => uint256) public pots; // offerHash => notionalPrincipal
    mapping(bytes32 => bool)   public swaps; // swapHash  => isLive?

    constructor(address gem_, address tub_) public {
        gem = TokenLike(gem_);
        tub = TubLike(tub_);
    }

    // --- Receiver Interface ---
    function offer(uint256 tag, uint256 cap, uint256 ttl, uint256 pot) public {
        uint256 due = sub(rmul(toRAY(pot), rpow(cap, mul(ttl, 1 days))) / 10 ** 9, pot);

        require(gem.transferFrom(msg.sender, address(this), due), "swaps: token transfer failed");
        require(pot > 0.05 ether, "swaps: offer must have a pot of more than 0.05 gems");

        bytes32 offerId = keccak256(
            abi.encodePacked(msg.sender, tag, cap, mul(ttl, 1 days))
        );

        require(pots[offerId] == 0, "swaps: pot not empty");
        pots[offerId] = pot;
        emit NewOffer(msg.sender, tag, cap, mul(ttl, 1 days), pot);
    }
    // function tweak() public {}

    // --- Payer Interface ---
    function take(
        address lad, uint256 tag, uint256 cap, uint256 ttl, uint256 pot
    ) public {
        bytes32 offerId = keccak256(abi.encodePacked(lad, tag, cap, ttl));
        bytes32 swapId = keccak256(
            abi.encodePacked(lad, msg.sender, tag, cap, ttl, now, pot, tub.rhi())
        );

        require(pots[offerId] > 0, "swaps: empty pot");
        require(pot > 0.05 ether,  "swaps: swap must have a pot of more than 0.05 gems");
        pots[offerId] = sub(pots[offerId], pot);
        uint256 due = sub(rmul(toRAY(pot), rpow(tag, ttl)) / 10 ** 9, pot);
        require(gem.transferFrom(address(msg.sender), address(this), due), "swaps: token transfer failed");

        swaps[swapId] = true;
        emit NewSwap(lad, msg.sender, tag, cap, ttl, now, pot, tub.rhi());
    }

    // --- Settlement ---
    function settle(
        address lad, address gal, uint256 pot, uint256 tag, 
        uint256 cap, uint256 rhi, uint256 start, uint256 ttl
    ) public {
        bytes32 swapId = keccak256(
            abi.encodePacked(lad, gal, tag, cap, ttl, start, pot, rhi)
        );
        
        require(swaps[swapId], "swaps: swap id must be of an active swap");
        require(now >= add(start, ttl), "swaps: swap must be past maturity");

        uint256 accruedInterest = wmul(pot, sub(tub.rhi(), rhi)) / 10 ** 9;
        uint256 takerPool = sub(rmul(toRAY(pot), rpow(tag, ttl)) / 10 ** 9, pot);
        uint256 providerPool = sub(rmul(toRAY(pot), rpow(cap, ttl)) / 10 ** 9, pot);
        
        // if the accrued interest is more than what the taker pooled, the rate moved against the provider
        if (takerPool < accruedInterest) {
            // if the provider owes more than what they pooled, the taker gets whats there
            if (sub(accruedInterest, takerPool) > providerPool) {
                require(gem.transfer(gal, add(takerPool, providerPool)), "swaps: token transfer failed");
            } else {
                // otherwise both parties get a payout, but the taker comes out ahead
                require(gem.transfer(gal, accruedInterest), "swaps: token transfer failed");
                require(gem.transfer(lad, sub(providerPool, sub(accruedInterest, takerPool))), "swaps: token transfer failed");
            }
        } else {
            // if the accrued interest is less than or equal to what the taker pooled, the provider comes out ahead
            require(gem.transfer(gal, accruedInterest), "swaps: token transfer failed");
            require(gem.transfer(lad, add(sub(takerPool, accruedInterest), providerPool)), "swaps: token transfer failed");
        }

        swaps[swapId] = false;
        emit Settled(lad, gal);
    }

    function toRAY(uint256 wad) internal pure returns(uint256 _ray) {
        _ray = mul(wad, 10 ** 9);
    }
}