/// cat.sol -- Dai liquidation module

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
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

pragma solidity >=0.5.12;

import "./lib.sol";

interface Kicker {
    function kick(address urn, address gal, uint256 tab, uint256 lot, uint256 bid)
        external returns (uint256);
}

interface VatLike {
    function ilks(bytes32) external view returns (
        uint256 Art,  // [wad]
        uint256 rate, // [ray]
        uint256 spot, // [ray]
        uint256 line, // [rad]
        uint256 dust  // [rad]
    );
    function urns(bytes32,address) external view returns (
        uint256 ink,  // [wad]
        uint256 art   // [wad]
    );
    function grab(bytes32,address,address,address,int256,int256) external;
    function hope(address) external;
    function nope(address) external;
}

interface VowLike {
    function fess(uint256) external;
}

contract Cat is LibNote {
    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Cat/not-authorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        address flip;  // Liquidator
        uint256 chop;  // Liquidation Penalty  [ray]
        uint256 dunk;  // Liquidation Quantity [rad]
    }

    mapping (bytes32 => Ilk) public ilks;

    uint256 public live;   // Active Flag
    VatLike public vat;    // CDP Engine
    VowLike public vow;    // Debt Engine
    uint256 public box;    // Max Dai out for liquidation        [rad]
    uint256 public litter; // Balance of Dai out for liquidation [rad]

    mapping (address => mapping (uint256 => uint256)) public tabs;  // per-contract per-auction dai to recapitalize [rad]

    // --- Events ---
    event Bite(
      bytes32 indexed ilk,
      address indexed urn,
      uint256 ink,
      uint256 art,
      uint256 tab,
      address flip,
      uint256 id
    );

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        live = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;

    uint256 constant MAX_DUNK = uint256(-1) / RAY;

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x > y) { z = y; } else { z = x; }
    }
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external note auth {
        if (what == "vow") vow = VowLike(data);
        else revert("Cat/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external note auth {
        if (what == "box") box = data;
        else revert("Cat/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, uint256 data) external note auth {
        if (what == "chop") ilks[ilk].chop = data;
        else if (what == "dunk" && data <= MAX_DUNK) ilks[ilk].dunk = data;
        else revert("Cat/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, address flip) external note auth {
        if (what == "flip") {
            vat.nope(ilks[ilk].flip);
            ilks[ilk].flip = flip;
            vat.hope(flip);
        }
        else revert("Cat/file-unrecognized-param");
    }

    // --- CDP Liquidation ---
    function bite(bytes32 ilk, address urn) external returns (uint256 id) {
        require(live == 1, "Cat/not-live");

        (uint256 ink, uint256 art) = vat.urns(ilk, urn);
        uint256 rate;
        uint256 dust;
        {
            uint256 spot;
            (, rate, spot,, dust) = vat.ilks(ilk);
            require(spot > 0 && mul(ink, spot) < mul(art, rate), "Cat/not-unsafe");
        }

        Ilk memory milk = ilks[ilk];
        uint256 dart;
        {
            uint256 room = sub(box, litter);

            // TODO(cmooney): test remaining space in litterbox if dusty
            require(litter < box && room >= dust, "Cat/liquidation-limit-hit");

            dart = min(art, min(milk.dunk, room) / rate);
        }

        uint256 dink = min(ink, mul(ink, dart) / art);

        require(dink <= 2**255 && dart <= 2**255, "Cat/overflow");

        // This may leave the CDP in a dusty state
        vat.grab(
            ilk, urn, address(this), address(vow), -int256(dink), -int256(dart)
        );

        { // Avoid stack too deep
            uint256 tab = mul(dart, rate);
            vow.fess(tab);
            litter = add(litter, tab);

            id = Kicker(milk.flip).kick({
                urn: urn,
                gal: address(vow),
                tab: rmul(tab, milk.chop),
                lot: dink,
                bid: 0
            });
            tabs[milk.flip][id] = tab;
            emit Bite(ilk, urn, dink, dart, tab, milk.flip, id);
        }
    }

    function claw(uint256 id) external note auth {
        litter = sub(litter, tabs[msg.sender][id]);
        delete tabs[msg.sender][id];
    }

    function cage() external note auth {
        live = 0;
    }
}
