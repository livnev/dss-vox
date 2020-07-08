// vox.sol -- target price adjusment
//
// Copyright (C) 2020 Lev Livnev <lev@liv.nev.org.uk>
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

pragma solidity ^0.5.15;

contract SpotLike {
    function par() external returns (uint256);
    function live() external returns (uint256);
    function file(bytes32 what, uint256 data) external;
}

contract DssVox {
    // --- auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external auth { wards[guy] = 1;  }
    function deny(address guy) external auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "DssVox/not-authorized");
        _;
    }

    uint256 public way;
    uint256 public tau;
    uint256 public cap;

    SpotLike public spot;

    // --- init ---
    constructor(address spot_) public {
        wards[msg.sender] = 1;
        spot = SpotLike(spot_);
        way = ONE;
        cap = ONE;
        tau = now;
    }

    // --- math ---
    uint256 constant ONE = 10 ** 27;
    function max(uint x, uint y) internal pure returns (uint z) {
        if (x < y) { z = y; } else { z = x; }
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / ONE;
    }
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    // --- administration ---
    function file(bytes32 what, uint256 data) external auth {
        require(spot.live() == 1, "DssVox/Spotter-not-live");
        if (what == 'way') way = data;
        if (what == 'cap') cap = data;
        else revert("DssVox/file-unrecognized-param");
    }

    // --- target price adjustment ---
    function prod() external {
        if (way == ONE) return;        // optimised
        uint256 age = sub(now, tau);
        if (age == 0) return;          // optimised
        tau = now;

        // no adjustment after cage
        if (spot.live() == 0) return;
        uint256 par = max(cap, rmul(rpow(way, age, ONE), spot.par()));
        spot.file("par", par);
    }
}
