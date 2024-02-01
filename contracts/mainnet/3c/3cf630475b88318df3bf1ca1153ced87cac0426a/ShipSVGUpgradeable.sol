// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ShipAssetsUpgradeable.sol";

contract ShipSVGUpgradeable is Initializable, AccessControlUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ShipAssetsUpgradeable public shipAssetsUpgradeable;

    function initialize(
        ShipAssetsUpgradeable _shipAssetsUpgradeable
    ) public initializer {
        shipAssetsUpgradeable = _shipAssetsUpgradeable;
    }

    function setShipAssetsUpgradeable(
        ShipAssetsUpgradeable _shipAssetsUpgradeable
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        shipAssetsUpgradeable = _shipAssetsUpgradeable;
    }

    // element functions

    function createStyleElement(
        string memory child
    ) public pure returns (string memory) {
        return string.concat("<style>", child, "</style>");
    }

    function createTextElement(
        string memory child,
        bool flipped
    ) public pure returns (string memory) {
        if (flipped) {
            return
                string.concat(
                    '<text transform="scale(1,-1)">',
                    child,
                    "</text>"
                );
        }

        return string.concat("<text>", child, "</text>");
    }

    function createStyleElements(
        string memory color,
        string memory thrusterColor
    ) public pure returns (string memory) {
        string memory output = "";

        string memory cssStyleElem = createStyleElement(
            string.concat(
                "tspan { text-anchor: middle; dominant-baseline: middle; font-family: Courier; font-size: 25px; white-space: pre; alignment-baseline: middle; fill: ",
                color,
                " }"
                " .thruster { fill: ",
                thrusterColor,
                "; animation: fadeInRight ease 0.10s alternate infinite; -webkit-animation: fadeInRight ease 0.10s alternate infinite; -moz-animation: fadeInRight ease 0.10s alternate infinite; -o-animation: fadeInRight ease 0.10s alternate infinite; -ms-animation: fadeInRight ease 0.10s alternate infinite; } @keyframes fadeInRight { from { opacity: 0; transform: translateX(300px); } to { opacity: 1; } } @-moz-keyframes fadeInRight { from { opacity: 0; transform: translateX(300px); } to { opacity: 1; } } @-webkit-keyframes fadeInRight { from { opacity: 0; transform: translateX(300px); } to { opacity: 1; } } @-o-keyframes fadeInRight { from { opacity: 0; transform: translateX(300px); } to { opacity: 1; } } @-ms-keyframes fadeInRight { from { opacity: 0; transform: translateX(300px); } to { opacity: 1; } }"
            )
        );

        string memory backgroundElement = createStyleElement(
            "svg { background: url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAzNTAgMzUwIiBoZWlnaHQ9IjEwMCUiIHdpZHRoPSIxMDAlIj48c3R5bGU+dHNwYW4ge2ZvbnQtZmFtaWx5OiBDb3VyaWVyO308L3N0eWxlPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiLz48dGV4dCBmb250LXNpemU9IjEyIiBmaWxsPSIjZmZmIj48dHNwYW4geD0iMTAwIiB5PSI1MCI+MDwvdHNwYW4+PHRzcGFuIHg9IjI4MCIgeT0iMTMwIj5PPC90c3Bhbj48dHNwYW4geD0iNTAiIHk9IjIwMCI+TzwvdHNwYW4+PHRzcGFuIHg9IjI4MCIgeT0iMzIwIj5PPC90c3Bhbj48dHNwYW4geD0iMTc1IiB5PSIxNzUiPm88L3RzcGFuPjx0c3BhbiB4PSIxNTAiIHk9IjI5MCI+bzwvdHNwYW4+PHRzcGFuIHg9IjMwMCIgeT0iMjAiPi48L3RzcGFuPjx0c3BhbiB4PSIyMDAiIHk9IjcwIj4uPC90c3Bhbj48dHNwYW4geD0iMzEwIiB5PSIyNTAiPi48L3RzcGFuPjx0c3BhbiB4PSI0MCIgeT0iMzEwIj4uPC90c3Bhbj48dHNwYW4geD0iMzAiIHk9IjkwIj4uPC90c3Bhbj48L3RleHQ+PC9zdmc+'); width: 350px; height: 350px; -webkit-animation: l_2_r 13s linear infinite; animation: l_2_r 13s linear infinite; } @-webkit-keyframes l_2_r { from {background-position: 0 0;} to {background-position: -1000px 0;} } @keyframes l_2_r { from {background-position: 0 0;} to {background-position: -1000px 0;} }"
        );

        output = string.concat(cssStyleElem, backgroundElement);

        return output;
    }

    function createSvgElement(
        string memory attrs,
        string memory child
    ) public pure returns (string memory) {
        string memory output = "";

        output = string.concat("<svg ", attrs, ">", child, "</svg>");

        return output;
    }

    function createTspanElement(
        string memory child,
        uint x,
        uint y,
        bool flipped
    ) public pure returns (string memory) {
        string memory output = "";

        string memory xStr = StringsUpgradeable.toString(x);
        string memory yStr = StringsUpgradeable.toString(y);

        string memory isFlipped = "";
        if (flipped) {
            isFlipped = "-";
        }

        string memory xAttr = string.concat("x='", "", xStr, "%'");
        string memory yAttr = string.concat("y='", isFlipped, yStr, "%'");

        string memory attrs = string.concat(xAttr, " ", yAttr);

        output = string.concat("<tspan ", attrs, ">", child, "</tspan>");

        return output;
    }

    function createTspanRow(
        ShipAssetsUpgradeable.Part[7] memory tspanParts,
        uint x,
        uint y,
        bool isFlipped
    ) public pure returns (string memory) {
        string memory output = "";

        string memory row = "";

        for (uint i = 0; i < tspanParts.length; i++) {
            if (equal(tspanParts[i].name, "Thruster")) {
                string memory flames = slice(1, 2, tspanParts[i].value);
                string memory booster = slice(3, 3, tspanParts[i].value);
                row = string.concat(
                    row,
                    '<tspan class="thruster">',
                    flames,
                    "</tspan>",
                    booster
                );
                continue;
            }

            row = string.concat(row, tspanParts[i].value);
        }

        output = createTspanElement(row, x, y, isFlipped);

        return output;
    }

    function createTspanRows(
        ShipAssetsUpgradeable.Battleship memory ship,
        bool onlyFlipped
    ) public pure returns (string memory tspanRows) {
        uint x = 50;

        if (onlyFlipped) {
            string memory outerRow = createTspanRow(
                ship.outerParts,
                x,
                36,
                onlyFlipped
            );

            string memory innerRow = createTspanRow(
                ship.innerParts,
                x,
                43,
                onlyFlipped
            );

            return string.concat(outerRow, innerRow);
        }

        string memory middleRow = createTspanRow(
            ship.middleParts,
            x,
            50,
            onlyFlipped
        );

        string memory innerRow2 = createTspanRow(
            ship.innerParts,
            x,
            57,
            onlyFlipped
        );

        string memory outerRow2 = createTspanRow(
            ship.outerParts,
            x,
            64,
            onlyFlipped
        );

        return string.concat(middleRow, innerRow2, outerRow2);
    }

    function createBattleshipSVG(
        uint seed
    ) public view returns (string memory) {
        ShipAssetsUpgradeable.Battleship memory ship = shipAssetsUpgradeable
            .buildBattleship(seed);

        string memory styleElems = createStyleElements(
            ship.color,
            ship.thrusterColor
        );

        string memory textElem1 = createTextElement(
            createTspanRows(ship, true),
            true
        );
        string memory textElem2 = createTextElement(
            createTspanRows(ship, false),
            false
        );

        string memory childSvgElems = string.concat(
            styleElems,
            textElem1,
            textElem2
        );

        string memory svgElem = createSvgElement(
            ' xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"',
            childSvgElems
        );

        return svgElem;
    }

    // utils

    function slice(
        uint256 begin,
        uint256 end,
        string memory text
    ) public pure returns (string memory) {
        bytes memory a = new bytes(end - begin + 1);
        for (uint i = 0; i <= end - begin; i++) {
            a[i] = bytes(text)[i + begin - 1];
        }
        return string(a);
    }

    function equal(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

