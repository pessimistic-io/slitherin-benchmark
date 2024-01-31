// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MintButton} from "./MintButton.sol";
import {IRenderer} from "./IRenderer.sol";

/// @author frolic.eth
/// @title  Mint Button renderer
contract MintButtonRenderer is IRenderer {
    MintButton public immutable token;

    event Initialized();

    constructor(MintButton _token) {
        token = _token;
        emit Initialized();
    }

    string internal constant mintButtonPaths =
        "%253Cpath%2520fill=%2522teal%2522%2520d=%2522M0%25200h100v100H0z%2522%253E%253C/path%253E%253Cpath%2520fill=%2522silver%2522%2520d=%2522M10%252038h80v23H10z%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522#000%2522%2520d=%2522M10%252060.5h80M89.5%252038v23%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522gray%2522%2520d=%2522M88.5%252039v21M11%252059.5h77%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522#DDD%2522%2520d=%2522M11.5%252039v20M11%252039.5h77%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522#fff%2522%2520d=%2522M10.5%252038v22M10%252038.5h79%2522%253E%253C/path%253E%253Cpath%2520fill=%2522#000%2522%2520d=%2522M20.25%252045h1.47l2.54%25206.22h.1L26.9%252045h1.46v8h-1.15v-5.79h-.07L24.79%252053h-.95l-2.36-5.78h-.08V53h-1.15v-8Zm9.78%25208v-6h1.17v6h-1.17Zm.6-6.93a.74.74%25200%25200%25201-.53-.2.66.66%25200%25200%25201-.22-.5c0-.18.07-.35.22-.48.14-.14.32-.21.52-.21s.38.07.52.2c.15.14.22.3.22.5a.73.73%25200%25200%25201-.74.7Zm3.3%25203.37V53h-1.16v-6h1.12v.98h.08c.13-.32.35-.58.64-.77.3-.2.67-.29%25201.13-.29.4%25200%2520.76.09%25201.07.26.3.17.55.42.71.76.17.33.26.75.26%25201.24V53H36.6v-3.68c0-.43-.11-.77-.34-1.02a1.2%25201.2%25200%25200%25200-.93-.37c-.27%25200-.51.06-.73.18-.2.12-.37.29-.5.52-.11.22-.17.49-.17.8ZM42.16%252047v.94h-3.28V47h3.28Zm-2.4-1.44h1.16v5.68c0%2520.22.04.4.1.51.07.11.16.19.27.23.1.04.23.06.35.06.1%25200%2520.18%25200%2520.25-.02l.16-.03.21.96a2.3%25202.3%25200%25200%25201-1.62-.04%25201.49%25201.49%25200%25200%25201-.64-.53%25201.56%25201.56%25200%25200%25201-.24-.9v-5.92Zm6.7%25207.44v-8h2.92c.57%25200%25201.04.1%25201.41.28a1.92%25201.92%25200%25200%25201%25201.12%25201.82c0%2520.33-.07.62-.19.85-.12.22-.28.4-.49.54-.2.14-.43.24-.67.3v.08a1.82%25201.82%25200%25200%25201%25201.41.92c.16.3.25.64.25%25201.06a1.97%25201.97%25200%25200%25201-1.17%25201.87c-.4.19-.91.28-1.53.28h-3.07Zm1.2-1.04h1.74c.58%25200%25201-.1%25201.24-.33.25-.23.38-.5.38-.84a1.32%25201.32%25200%25200%25200-.74-1.2%25201.75%25201.75%25200%25200%25200-.84-.19h-1.78v2.56Zm0-3.5h1.62c.27%25200%2520.51-.05.73-.16a1.16%25201.16%25200%25200%25200%2520.71-1.1c0-.34-.11-.61-.35-.84-.23-.22-.58-.33-1.06-.33h-1.65v2.43Zm9.7%25202.05V47h1.17v6h-1.15v-1.04h-.06a1.91%25201.91%25200%25200%25201-1.8%25201.12c-.38%25200-.72-.09-1.02-.26-.3-.17-.52-.42-.7-.76a2.79%25202.79%25200%25200%25201-.24-1.24V47h1.16v3.68c0%2520.4.12.73.34.97.23.24.52.37.89.37a1.43%25201.43%25200%25200%25200%25201.2-.66c.14-.23.2-.5.2-.85ZM62.89%252047v.94H59.6V47h3.28Zm-2.4-1.44h1.17v5.68c0%2520.22.03.4.1.51.07.11.15.19.26.23.11.04.23.06.36.06.1%25200%2520.17%25200%2520.24-.02l.17-.03.2.96a2.3%25202.3%25200%25200%25201-1.62-.04%25201.46%25201.46%25200%25200%25201-.63-.53%25201.56%25201.56%25200%25200%25201-.25-.9v-5.92Zm6.5%25201.44v.94H63.7V47h3.28Zm-2.4-1.44h1.16v5.68c0%2520.22.03.4.1.51.07.11.16.19.26.23.11.04.23.06.36.06.1%25200%2520.18%25200%2520.25-.02l.16-.03.21.96a2.3%25202.3%25200%25200%25201-1.62-.04%25201.43%25201.43%25200%25200%25201-.64-.53%25201.56%25201.56%25200%25200%25201-.25-.9v-5.92Zm6.15%25207.56a2.6%25202.6%25200%25200%25201-2.45-1.47c-.23-.46-.35-1-.35-1.62%25200-.63.12-1.17.35-1.64a2.6%25202.6%25200%25200%25201%25202.45-1.47%25202.6%25202.6%25200%25200%25201%25202.45%25201.47c.23.47.34%25201.01.34%25201.64%25200%2520.62-.11%25201.16-.34%25201.62a2.6%25202.6%25200%25200%25201-2.45%25201.47Zm0-.98c.36%25200%2520.67-.1.9-.29.25-.2.42-.45.54-.77a3.23%25203.23%25200%25200%25200%25200-2.11%25201.9%25201.9%25200%25200%25200-.53-.78c-.24-.2-.55-.3-.91-.3-.37%25200-.67.1-.91.3-.24.2-.42.46-.54.78a3.21%25203.21%25200%25200%25200%25200%25202.11c.12.32.3.58.54.77.24.2.54.3.91.3Zm5.26-2.7V53h-1.16v-6h1.12v.98h.07c.14-.32.36-.58.65-.77.3-.2.67-.29%25201.12-.29.41%25200%2520.77.09%25201.08.26.3.17.54.42.71.76.17.33.25.75.25%25201.24V53h-1.16v-3.68c0-.43-.12-.77-.34-1.02a1.2%25201.2%25200%25200%25200-.94-.37c-.27%25200-.5.06-.72.18-.2.12-.37.29-.5.52-.12.22-.18.49-.18.8Z%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522#000%2522%2520d=%2522M59%252057.5h1v1h1v1h1v1h1v1h1v1h1v1h1v1h1v1h1v1h1v1h1v1h-4v2h1v2h1v1h-1v1h-1v-1h-1v-2h-1v-2h-2v1h-1v1h-1v1h-1v-15Zm0%25200V56%2522%253E%253C/path%253E%253Cpath%2520fill=%2522#fff%2522%2520d=%2522M61%252070.5h-1v-11h1v1h1v1h1v1h1v1h1v1h1v1h1v1h1v1h-3v3h1v2h1v1h-1v-2h-1v-2h-1v-1h-2v1h-1v1Z%2522%253E%253C/path%253E%253Cpath%2520stroke=%2522#fff%2522%2520d=%2522M60%252058v1.5M60%252072v-1.5m0%25200h1v-1h1v-1h2v1h1m-5%25201v-11m5%252010v1m0-1v-2h3m-2%25204h-1v-1m1%25201v1m0-1v-1h-1m1%25202v1h1v-1h-1Zm3.5-5H68m0%25200v-1h-1v-1h-1v-1h-1v-1h-1v-1h-1v-1h-1v-1h-1v-1h-1%2522%253E%253C/path%253E";

    function mintButtonImage() public pure returns (string memory) {
        return string.concat(
            "%253Csvg%2520xmlns=%2522http://www.w3.org/2000/svg%2522%2520xmlns:xlink=%2522http://www.w3.org/1999/xlink%2522%2520width=%2522600%2522%2520height=%2522600%2522%2520fill=%2522none%2522%2520viewBox=%25220%25200%2520100%2520100%2522%253E",
            mintButtonPaths,
            "%253C/svg%253E"
        );
    }

    function mintButtonErrorImage(
        string memory tokenIdString,
        string memory mintBlockString
    ) public pure returns (string memory) {
        return string.concat(
            "%253Csvg%2520xmlns=%2522http://www.w3.org/2000/svg%2522%2520xmlns:xlink=%2522http://www.w3.org/1999/xlink%2522%2520width=%2522600%2522%2520height=%2522600%2522%2520fill=%2522none%2522%2520viewBox=%25220%25200%2520100%2520100%2522%253E%253Cpath%2520fill=%2522black%2522%2520d=%2522M0%25200h100v100H0z%2522%253E%253C/path%253E%253Cg%253E%253CanimateTransform%2520attributeName=%2522transform%2522%2520type=%2522translate%2522%2520values=%25220%25200;%25200%25200;%25200%25200;%2520-2%25200;%25200%25200;%2520-10%2520-10;%25200%25200;%2520-10%2520-5;%25200%25200;%25200%2520-50;%25200%25200;%2520-40%252060%2522%2520dur=%25221s%2522%2520fill=%2522freeze%2522%2520calcMode=%2522discrete%2522%2520additive=%2522sum%2522%253E%253C/animateTransform%253E%253CanimateTransform%2520attributeName=%2522transform%2522%2520type=%2522scale%2522%2520values=%25221%25201;%25201%25201;%25201%25201;%25201.05%25201;%25201%25201;%25201.05%2520.8;%25201.1%2520.8;%25201.1%25201.1;%25201.4%2520.5;%25201.4%2520.5;%25201.4%2520.5;%25201.6%2520-.5%2522%2520dur=%25221s%2522%2520fill=%2522freeze%2522%2520calcMode=%2522discrete%2522%2520additive=%2522sum%2522%253E%253C/animateTransform%253E",
            mintButtonPaths,
            "%253C/g%253E%253Cg%253E%253Canimate%2520attributeName=%2522opacity%2522%2520values=%25220;%25201%2522%2520dur=%25222.5s%2522%2520fill=%2522freeze%2522%2520calcMode=%2522discrete%2522%253E%253C/animate%253E%253Cpath%2520fill=%2522#00A%2522%2520d=%2522M0%25200h100v100H0z%2522%253E%253C/path%253E%253CforeignObject%2520x=%25220%2522%2520y=%25220%2522%2520width=%2522100%2525%2522%2520height=%2522100%2525%2522%253E%253Cstyle%253E*%2520%257B%2520box-sizing:%2520border-box;%2520margin:%25200;%2520%257D%253C/style%253E%253Cdiv%2520xmlns=%2522http://www.w3.org/1999/xhtml%2522%2520style=%2522height:100%2525;display:flex;flex-direction:column;justify-content:center;gap:1.25em;padding:2em;color:#fff;font-size:4px;font-weight:semibold;line-height:1.25em;font-family:ui-monospace,%2520SFMono-Regular,%2520Menlo,%2520Monaco,%2520Consolas,%2520&#x27;Liberation%2520Mono&#x27;,%2520&#x27;Courier%2520New&#x27;,%2520monospace%2522%253E%253Cp%2520style=%2522align-self:center;color:#00a;background-color:#aaa;font-weight:bold;padding:0%25201em%2522%253EMint%2520Button%253C/p%253E%253Cp%253EA%2520fatal%2520error%2520occurred.%2520Program%2520terminated.%253C/p%253E%253Cp%253EPress%2520ANY%2520KEY%2520to%2520restart.%253C/p%253E%253Cp%253E%253Cbr/%253E***%2520ADDR%2520",
            tokenIdString,
            "%253Cbr/%253E***%2520PTR%2520",
            mintBlockString,
            "%253C/p%253E%253C/div%253E%253C/foreignObject%253E%253C/g%253E%253C/svg%253E"
        );
    }

    function tokenURI(uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        string memory tokenIdString = toString(tokenId);
        string memory mintBlockString = toString(token.mintBlock(tokenId));
        string memory image = token.lastTokenId() == tokenId
            ? mintButtonImage()
            : mintButtonErrorImage(tokenIdString, mintBlockString);

        return string.concat(
            "data:application/json,",
            "%7B%22name%22:%22Mint%20Button%20#",
            tokenIdString,
            "%22,%22description%22:%22An%20experimental%20open%20edition%20by%20frolic.eth.%20Mint%20a%20button%20for%200.00144%20ETH.%20Minting%20closes%20~48%20hours%20after%20the%20last%20mint.%20The%20owner%20of%20the%20last%20mint%20can%20burn%20their%20button%20to%20withdraw%20100%25%20of%20the%20mint%20fees%20collected.%20GLHF!%5Cn%5Cn---%5Cn%5CnMint%20Button%20#",
            tokenIdString,
            "%20collected%20at%20block%20",
            mintBlockString,
            ".%22,%22external_url%22:%22https://twitter.com/frolic%22,%22image%22:%22data:image/svg+xml,",
            image,
            "%22%7D"
        );
    }

    function toString(uint256 value)
        internal
        pure
        returns (string memory str)
    {
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
            // We will need 1 word for the trailing zeros padding, 1 word for the length,
            // and 3 words for a maximum of 78 digits. Total: 5 * 0x20 = 0xa0.
            let m := add(mload(0x40), 0xa0)
            // Update the free memory pointer to allocate.
            mstore(0x40, m)
            // Assign the `str` to the end.
            str := sub(m, 0x20)
            // Zeroize the slot after the string.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                str := sub(str, 1)
                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))
                // Keep dividing `temp` until zero.
                temp := div(temp, 10)
                // prettier-ignore
                if iszero(temp) { break }
            }

            let length := sub(end, str)
            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 0x20)
            // Store the length.
            mstore(str, length)
        }
    }
}

