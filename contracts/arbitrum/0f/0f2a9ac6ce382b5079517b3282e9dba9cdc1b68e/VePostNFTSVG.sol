// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Base64.sol";

contract VePostNFTSVG {
    function buildVePost(
        uint256 tokenId,
        uint8 typeVePost, //0: None, 1: Token, 1: LP NFT
        uint256 startTimeLock,
        uint256 endTimeLock,
        uint256 currentTime,
        uint256 boost,
        uint256 currentWeight
    ) external pure returns (string memory) {
        bytes memory svgImage = _buildImage(
            tokenId,
            typeVePost,
            startTimeLock,
            endTimeLock,
            currentTime,
            boost,
            currentWeight
        );

        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "vePost NFT #',
            _toString(tokenId),
            '",',
            '"description": "vePost NFT by post.tech",',
            '"image": "',
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(svgImage)
            ),
            '"',
            "}"
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(dataURI)
                )
            );
    }

    function _buildImage(
        uint256 tokenId,
        uint8 typeVePost, //0: None, 1: Token, 1: LP NFT
        uint256 startTimeLock,
        uint256 endTimeLock,
        uint256 currentTime,
        uint256 boost,
        uint256 currentWeight
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                '<svg width="202" height="278" viewBox="0 0 420 578" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#a)">',
                _buildBackground(typeVePost),
                '<g filter="url(#d)"><circle cx="273.285" cy="263.2" r="145.85" fill="#729BEC"/></g><g filter="url(#e)"><circle cx="209.635" cy="501.712" r="124.055" fill="#729BEC"/></g><g opacity=".6" filter="url(#f)"><circle cx="125.865" cy="191.515" r="83.445" fill="#729BEC"/></g></g><path d="M117 0h185v28c0 8.837-7.163 16-16 16H133c-8.837 0-16-7.163-16-16V0Z" fill="#fff" fill-opacity=".1"/>',
                _buildTypeNft(typeVePost),
                '<rect x="19.635" y="528" width="380" height="28" rx="8" fill="#283975" fill-opacity=".3"/><text fill="#F8FAFC" xml:space="preserve" style="white-space:pre" font-family="Arial" font-size="14" letter-spacing="0em"><tspan x="156.135" y="546.854">&#xa9;post.tech, 2023</tspan></text><path d="M313.937 291.002a17.453 17.453 0 0 1-9.379-3.831L86.304 112.39c-7.522-6.094-8.68-17.131-2.587-24.654 6.093-7.522 17.133-8.68 24.654-2.587l218.254 174.78c7.522 6.094 8.681 17.132 2.587 24.654-3.835 4.735-9.631 6.949-15.275 6.419Z" fill="url(#g)" opacity=".3"/>',
                _buildLocation(startTimeLock, endTimeLock, currentTime),
                _buildInformation(
                    startTimeLock,
                    endTimeLock,
                    tokenId,
                    boost,
                    currentWeight
                ),
                '<g filter="url(#i)"><path d="m337.913 286.625-11.255-41.042h-.002v-.002l-40.993-5.08c-1.781-2.739-5.492-7.07-12.468-9.974-7.326-12.498-20.369-14.833-30.058-15.434-18.608-.14-27.792 12.666-31.721 19.545 1.579-4.586 2.083-11.227 12.316-19.726 9.52-7.927 19.643-19.307 16.692-31.344-4.683-19.265-10.038-41.088 7.103-63.988-1.035.671-74.921 21.292-73.775 106.935 0 .476-1.426-21.827-21.054-35.719-18.69-14.344-42.793-28.394-45.253-47.799 0 0-43.577 103.384 37.984 140.348 8.081 3.663-3.65 17.335-11.688 21.096-5.922 2.955-20.942 11.142-20.942 11.142-16.473 9.016-25.206 25.808-31.246 32.658-.125.14-.196.21-.196.21.014 0 22.689-16.078 64.6-22.274 46.035-4.276 64.348-18.385 65.878-19.331 12.862-7.941 19.211-24.481 29.922-36.037 19.236-20.752 32.341-26.286 39.033-27.663l14.465 41.421.002-.001 42.656 2.059Z" fill="#fff" fill-opacity=".15"/></g><path d="M109.056 10.611H25.143c-8.837 0-16 7.164-16 16V550.96c0 8.837 7.163 16 16 16h367.654c8.837 0 16-7.163 16-16V26.611c0-8.836-7.163-16-16-16h-83.913" stroke="#fff" stroke-opacity=".4" stroke-width="2"/><defs><filter id="b" x="-129.476" y="-158.656" width="392" height="392" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="45" result="effect1_foregroundBlur_5235_408195"/></filter><filter id="c" x="9.486" y="-241.13" width="617.825" height="541.897" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="45" result="effect1_foregroundBlur_5235_408195"/></filter><filter id="d" x="30.209" y="20.124" width="486.151" height="486.152" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="48.613" result="effect1_foregroundBlur_5235_408195"/></filter><filter id="e" x="-18.889" y="273.188" width="457.048" height="457.048" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="52.235" result="effect1_foregroundBlur_5235_408195"/></filter><filter id="f" x="-54.806" y="10.844" width="361.342" height="361.341" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="48.613" result="effect1_foregroundBlur_5235_408195"/></filter><filter id="i" x="69.022" y="107.245" width="281.225" height="253.542" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="6.168" result="effect1_foregroundBlur_5235_408195"/></filter><linearGradient id="g" x1="173.928" y1="30.505" x2="268.083" y2="302.249" gradientUnits="userSpaceOnUse"><stop stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient><linearGradient id="h" x1="196.956" y1="107.542" x2="185.747" y2="269.026" gradientUnits="userSpaceOnUse"><stop stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient><clipPath id="a"><rect x=".135" width="419" height="578" rx="24" fill="#fff"/></clipPath></defs></svg>'
            );
    }

    function _buildTypeNft(
        uint8 typeVePost
    ) internal pure returns (string memory) {
        string memory typeStringVePost;
        string memory locationText;

        if (typeVePost == 1) {
            typeStringVePost = "vePost NFT";
            locationText = "160.5";
        } else if (typeVePost == 2) {
            typeStringVePost = "vePost LP NFT";
            locationText = "147.5";
        } else {
            typeStringVePost = "vePost Empty";
            locationText = "160.5";
        }

        return
            string(
                abi.encodePacked(
                    '<text fill="#F8FAFC" xml:space="preserve" style="white-space:pre" font-family="Arial" font-size="18" font-weight="bold" letter-spacing="0em">',
                    '<tspan x="',
                    locationText,
                    '" y="30.1592">',
                    typeStringVePost,
                    "</tspan> </text>"
                )
            );
    }

    function _buildLocation(
        uint256 startTimeLock,
        uint256 endTimeLock,
        uint256 currentTime
    ) internal pure returns (string memory) {
        uint256 phaseTime = (endTimeLock - startTimeLock) / 7;
        uint256 currentPhase = currentTime - startTimeLock;
        string memory cx;
        string memory cy;

        if (currentPhase > 6 * phaseTime) {
            cx = "316.5";
            cy = "275.464";
        } else if (currentPhase > 5 * phaseTime) {
            cx = "279.5";
            cy = "246.463";
        } else if (currentPhase > 4 * phaseTime) {
            cx = "242.5";
            cy = "218.464";
        } else if (currentPhase > 3 * phaseTime) {
            cx = "204.5";
            cy = "186.464";
        } else if (currentPhase > 2 * phaseTime) {
            cx = "171.5";
            cy = "161.463";
        } else if (currentPhase > phaseTime) {
            cx = "134.5";
            cy = "130.464";
        } else {
            cx = "93.5";
            cy = "100.464";
        }

        return
            string(
                abi.encodePacked(
                    string(
                        abi.encodePacked(
                            '<path d="m96.747 98.139 55.912 44.667 55.912 44.668 111.824 89.335" stroke="url(#h)" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>',
                            '<circle opacity=".1" cx="',
                            cx,
                            '" cy="',
                            cy,
                            '" r="32" fill="#fff"/>'
                        )
                    ),
                    string(
                        abi.encodePacked(
                            '<circle opacity=".3" cx="',
                            cx,
                            '" cy="',
                            cy,
                            '" r="18" fill="#fff"/>'
                        )
                    ),
                    string(
                        abi.encodePacked(
                            '<circle cx="',
                            cx,
                            '" cy="',
                            cy,
                            '" r="10" fill="#fff"/>'
                        )
                    )
                )
            );
    }

    function _buildBackground(
        uint8 lockType
    ) internal pure returns (string memory) {
        string memory color1 = lockType == 2 ? "#3088EB" : "#1565FE";
        string memory color2 = lockType == 2 ? "#6F49DC" : "#4473FF";
        string memory color3 = lockType == 2 ? "#8241D8" : "#567BFF";

        return
            string(
                abi.encodePacked(
                    '<path d="M394.809 0h-371c-13.255 0-24 10.745-24 24v530c0 13.255 10.745 24 24 24h371c13.254 0 24-10.745 24-24V24c0-13.255-10.746-24-24-24Z" fill="',
                    color1,
                    '"/><g filter="url(#b)"><circle cx="66.524" cy="37.344" r="106" fill="',
                    color2,
                    '"/></g>',
                    '<g filter="url(#c)"><ellipse cx="318.399" cy="29.819" rx="218.913" ry="180.949" fill="',
                    color3,
                    '"/></g>'
                )
            );
    }

    function _buildInformation(
        uint256 startTimeLock,
        uint256 endTimeLock,
        uint256 tokenId,
        uint256 boost,
        uint256 currentWeight
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<g filter="url(#filter5_b_544_23454)"><rect x="20" y="372.884" width="379" height="140" rx="12" fill="#283975" fill-opacity=".5"/><g clip-path="url(#clip1_544_23454)" font-family="Arial" font-size="20"><text fill="#E2E8F0" xml:space="preserve" style="white-space:pre" letter-spacing="0em"> <tspan x="36" y="408.817">ID: </tspan> </text><text fill="#F1F5F9" xml:space="preserve" style="white-space:pre" font-weight="bold" letter-spacing="-.005em" text-anchor="end"> <tspan x="380" y="408.934">#',
                    _toString(tokenId),
                    '</tspan></text></g><g clip-path="url(#clip2_544_23454)" font-family="Arial" font-size="20"><text fill="#E2E8F0" xml:space="preserve" style="white-space:pre" letter-spacing="0em"><tspan x="36" y="449.817">Boost: </tspan></text><text fill="#F1F5F9" xml:space="preserve" style="white-space:pre" font-weight="bold" letter-spacing="-.005em" text-anchor="end"><tspan x="380" y="449.817">',
                    _buildBoost(startTimeLock, endTimeLock, boost),
                    '%</tspan></text></g><g clip-path="url(#clip3_544_23454)" font-family="Arial" font-size="20"><text fill="#E2E8F0" xml:space="preserve" style="white-space:pre" letter-spacing="0em"><tspan x="36" y="489.817">Current Power: </tspan></text><text fill="#F1F5F9" xml:space="preserve" style="white-space:pre" font-weight="bold" letter-spacing="-.005em" text-anchor="end"><tspan x="380" y="489.817">',
                    _buildPower(currentWeight),
                    "</tspan></text></g></g>"
                )
            );
    }

    function _buildBoost(
        uint256 startTime,
        uint256 endTime,
        uint256 boosted
    ) public pure returns (string memory) {
        uint256 boostPerTime = ((endTime - startTime) * 10_000) / 208 weeks;
        uint256 boost = (boosted * boostPerTime) / 10_000;
        uint256 decimal = boost % 100;
        string memory decimalStr = _toString(decimal);
        if (bytes(decimalStr).length == 0) {
            decimalStr = ".00";
        } else if (bytes(decimalStr).length == 1) {
            decimalStr = string.concat(".0", decimalStr);
        } else {
            decimalStr = string.concat(".", decimalStr);
        }

        string memory numberStr = _toString(boost / 100);

        return string.concat(numberStr, decimalStr);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _buildPower(uint256 _num) internal pure returns (string memory) {
        if (_num == 0) {
            return "0";
        }

        string memory numberStr = _numberWithCommas(uint256(_num / 1e18));

        if (_num / 1e18 == 0) {
            numberStr = "0";
        }
        return string.concat(numberStr, _decimal(_num));
    }

    function _decimal(uint256 _num) internal pure returns (string memory) {
        uint256 mod = _num % 1e18;
        uint256 decimal = mod / 1e15;
        string memory decimalStr = _toString(decimal);
        if (bytes(decimalStr).length == 2) {
            decimalStr = string.concat("0", decimalStr);
        } else if (bytes(decimalStr).length == 1) {
            decimalStr = string.concat("00", decimalStr);
        }
        return string.concat(".", decimalStr);
    }

    function _numberWithCommas(
        uint256 _num
    ) internal pure returns (string memory) {
        string memory numStr = _toString(_num);
        uint256 length = bytes(numStr).length;
        if (length == 1) return numStr;
        uint256 commaCount = (length - 1) / 3;
        bytes memory result = new bytes(length + commaCount);

        uint256 i = length - 1;
        uint256 j = result.length - 1;
        uint256 commaAdded = 0;

        while (true) {
            result[j--] = bytes(numStr)[i--];
            commaAdded++;
            if (commaAdded % 3 == 0 && i >= 0) {
                result[j--] = ",";
            }
            if (i == 0) {
                result[j] = bytes(numStr)[0];
                break;
            }
        }
        return string(result);
    }
}

