// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "./Base64.sol";
import "./Strings.sol";

import "./IERC20.sol";

library NFTRenderer {
    struct RenderParams {
        address owner;
        uint256 amount;
        uint256 futureAmount;
    }

    function render(RenderParams memory params)
        internal
        view
        returns (string memory)
    {

        string memory image = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480'>",
            "<style>.tokens { font: bold 30px sans-serif; }",
            ".fee { font: normal 26px sans-serif; }",
            ".tick { font: normal 18px sans-serif; }</style>",
            renderBackground(params.owner),
            renderTop(params.amount, params.futureAmount),
            renderBottom(),
            "</svg>"
        );

        string memory description = renderDescription(params.owner,params.amount);

        string memory json = string.concat(
            '{"name":"Heru CFA Strategy Position NFT",',
            '"description":"',
            description,
            '",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '"}'
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            );
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    function renderBackground(
        address owner
    ) internal view returns (string memory background) {
        bytes32 key = keccak256(abi.encodePacked(owner, block.timestamp));
        uint256 hue = uint256(key) % 360;

        background = string.concat(
            '<rect width="300" height="480" fill="hsl(',
            Strings.toString(hue),
            ',40%,40%)"/>',
            '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(',
            Strings.toString(hue),
            ',100%,50%)" stroke="#000"/>'
        );
    }

    function renderTop(
uint256 amount,uint256 futureAmount    ) internal pure returns (string memory top) {
        top = string.concat(
            '<rect x="30" y="87" width="240" height="42"/>',
            '<text x="39" y="120" class="tokens" fill="#fff">',
            Strings.toString(amount),
            "/",
            Strings.toString(futureAmount),
            "</text>"
        );
    }

    function renderBottom()
        internal
        pure
        returns (string memory bottom)
    {
        bottom = string.concat(
            '<rect x="30" y="342" width="240" height="24"/>',
            '<text x="39" y="360" class="tick" fill="#fff">Lower tick: ',
            //tickToText(lowerTick),
            "</text>",
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">Upper tick: ',
            //tickToText(upperTick),
            "</text>"
        );
    }

    function renderDescription(address owner,uint256 amount
    ) internal pure returns (string memory description) {
        description = string.concat(Strings.toHexString(uint160(owner), 20), " has deposited " , Strings.toString(amount));
    }
}

