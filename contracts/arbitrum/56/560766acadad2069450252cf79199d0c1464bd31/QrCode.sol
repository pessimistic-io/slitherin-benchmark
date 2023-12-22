// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { Strings } from "./Strings.sol";
import { Base64 } from "./Base64.sol";
import {     ERC721URIStorage,     ERC721 } from "./ERC721URIStorage.sol";
import { Counters } from "./Counters.sol";
import { Ownable } from "./Ownable.sol";
import { DynamicBuffer } from "./DynamicBuffer.sol";
import { QarbCodesInterface } from "./QarbCodesInterface.sol";

struct QRMatrix {
    uint256[29][29] matrix;
    uint256[29][29] reserved;
}

contract QrCode {
    function _generateQRCode(
        string memory handle,
        string memory color
    ) internal pure returns (string memory) {
        // 1. Create base matrix
        QRMatrix memory qrMatrix = _createBaseMatrix();
        // 2. Encode Data
        uint8[] memory encoded = _encode(string(abi.encodePacked(handle)));
        // 3. Generate buff
        uint256[44] memory buf = _generateBuf(encoded);

        // 4. Augument ECCs
        uint256[70] memory bufWithECCs = _augumentECCs(buf);

        // 5. put data into matrix
        _putData(qrMatrix, bufWithECCs);

        // 6. mask data
        _maskData(qrMatrix);

        // 7. Put format info
        _putFormatInfo(qrMatrix);
        // emit MatrixCreated(qrMatrix.matrix);

        // 8. Compose SVG and convert to base64
        return _generateQRURIByteVersion(qrMatrix, color);
    }

    function _createBaseMatrix() internal pure returns (QRMatrix memory) {
        QRMatrix memory _qrMatrix;
        uint256 size = 29;
        uint8[2] memory aligns = [4, 20];

        _qrMatrix = _blit(
            _qrMatrix,
            0,
            0,
            9,
            9,
            [0x7f, 0x41, 0x5d, 0x5d, 0x5d, 0x41, 0x17f, 0x00, 0x40]
        );

        _qrMatrix = _blit(
            _qrMatrix,
            size - 8,
            0,
            8,
            9,
            [0x100, 0x7f, 0x41, 0x5d, 0x5d, 0x5d, 0x41, 0x7f, 0x00]
        );

        _blit(
            _qrMatrix,
            0,
            size - 8,
            9,
            8,
            [
                uint16(0xfe),
                uint16(0x82),
                uint16(0xba),
                uint16(0xba),
                uint16(0xba),
                uint16(0x82),
                uint16(0xfe),
                uint16(0x00),
                uint16(0x00)
            ]
        );

        for (uint256 i = 9; i < size - 8; ++i) {
            _qrMatrix.matrix[6][i] = _qrMatrix.matrix[i][6] = ~i & 1;
            _qrMatrix.reserved[6][i] = _qrMatrix.reserved[i][6] = 1;
        }

        // alignment patterns
        for (uint8 i = 0; i < 2; ++i) {
            uint8 minj = i == 0 || i == 1 ? 1 : 0;
            uint8 maxj = i == 0 ? 1 : 2;
            for (uint8 j = minj; j < maxj; ++j) {
                _blit(
                    _qrMatrix,
                    aligns[i],
                    aligns[j],
                    5,
                    5,
                    [
                        uint16(0x1f),
                        uint16(0x11),
                        uint16(0x15),
                        uint16(0x11),
                        uint16(0x1f),
                        uint16(0x00),
                        uint16(0x00),
                        uint16(0x00),
                        uint16(0x00)
                    ]
                );
            }
        }

        return _qrMatrix;
    }

    function _encode(string memory str) internal pure returns (uint8[] memory) {
        bytes memory byteString = bytes(str);
        uint8[] memory encodedArr = new uint8[](byteString.length);

        for (uint8 i = 0; i < encodedArr.length; i++) {
            encodedArr[i] = uint8(byteString[i]);
        }

        return encodedArr;
    }

    function _generateBuf(
        uint8[] memory data
    ) internal pure returns (uint256[44] memory) {
        uint256[44] memory buf;
        uint256 dataLen = data.length;
        uint8 maxBufLen = 44;

        uint256 bits = 0;
        uint256 remaining = 8;

        (buf, bits, remaining) = _pack(buf, bits, remaining, 4, 4, 0);
        (buf, bits, remaining) = _pack(buf, bits, remaining, dataLen, 8, 0);

        for (uint8 i = 0; i < dataLen; ++i) {
            (buf, bits, remaining) = _pack(
                buf,
                bits,
                remaining,
                data[i],
                8,
                i + 1
            );
        }

        (buf, bits, remaining) = _pack(buf, bits, remaining, 0, 4, dataLen + 1);

        for (uint256 i = data.length + 2; i < maxBufLen - 1; i++) {
            buf[i] = 0xec;
            buf[i + 1] = 0x11;
        }

        return buf;
    }

    function _maskData(QRMatrix memory _qrMatrix) internal pure {
        for (uint256 i = 0; i < 29; ++i) {
            for (uint256 j = 0; j < 29; ++j) {
                if (_qrMatrix.reserved[i][j] == 0) {
                    if (j % 3 == 0) {
                        _qrMatrix.matrix[i][j] ^= 1;
                    } else {
                        _qrMatrix.matrix[i][j] ^= 0;
                    }
                }
            }
        }
    }

    function _augumentECCs(
        uint256[44] memory poly
    ) internal pure returns (uint256[70] memory) {
        uint8 nblocks = 1;
        uint8[26] memory genpoly = [
            173,
            125,
            158,
            2,
            103,
            182,
            118,
            17,
            145,
            201,
            111,
            28,
            165,
            53,
            161,
            21,
            245,
            142,
            13,
            102,
            48,
            227,
            153,
            145,
            218,
            70
        ];

        uint8[2] memory subsizes = [0, 44];
        uint256 nitemsperblock = 44;
        uint256[26][1] memory eccs;
        uint256[70] memory result;
        uint256[44] memory partPoly;

        for (uint256 i; i < 44; i++) {
            partPoly[i] = poly[i];
        }

        eccs[0] = _calculateECC(partPoly, genpoly);

        for (uint8 i = 0; i < nitemsperblock; ++i) {
            for (uint8 j = 0; j < nblocks; ++j) {
                result[i] = poly[subsizes[j] + i];
            }
        }
        for (uint8 i = 0; i < genpoly.length; ++i) {
            for (uint8 j = 0; j < nblocks; ++j) {
                result[i + 44] = eccs[j][i];
            }
        }

        return result;
    }

    function _calculateECC(
        uint256[44] memory poly,
        uint8[26] memory genpoly
    ) internal pure returns (uint256[26] memory) {
        uint256[256] memory GF256_MAP;
        uint256[256] memory GF256_INVMAP;
        uint256[70] memory modulus;
        uint8 polylen = uint8(poly.length);
        uint8 genpolylen = uint8(genpoly.length);
        uint256[26] memory result;
        uint256 gf256_value = 1;

        GF256_INVMAP[0] = 0;

        for (uint256 i = 0; i < 255; ++i) {
            GF256_MAP[i] = gf256_value;
            GF256_INVMAP[gf256_value] = i;
            gf256_value = (gf256_value * 2) ^ (gf256_value >= 128 ? 0x11d : 0);
        }

        for (uint8 i = 0; i < 44; i++) {
            modulus[i] = poly[i];
        }

        for (uint8 i = 44; i < 70; ++i) {
            modulus[i] = 0;
        }

        for (uint8 i = 0; i < polylen; ) {
            uint256 idx = modulus[i++];
            if (idx > 0) {
                uint256 quotient = GF256_INVMAP[idx];
                for (uint8 j = 0; j < genpolylen; ++j) {
                    modulus[i + j] ^= GF256_MAP[(quotient + genpoly[j]) % 255];
                }
            }
        }

        for (uint8 i = 0; i < modulus.length - polylen; i++) {
            result[i] = modulus[polylen + i];
        }

        return result;
    }

    function _pack(
        uint256[44] memory buf,
        uint256 bits,
        uint256 remaining,
        uint256 x,
        uint256 n,
        uint256 index
    ) internal pure returns (uint256[44] memory, uint256, uint256) {
        uint256[44] memory newBuf = buf;
        uint256 newBits = bits;
        uint256 newRemaining = remaining;

        if (n >= remaining) {
            newBuf[index] = bits | (x >> (n -= remaining));
            newBits = 0;
            newRemaining = 8;
        }
        if (n > 0) {
            newBits |= (x & ((1 << n) - 1)) << (newRemaining -= n);
        }

        return (newBuf, newBits, newRemaining);
    }

    function _blit(
        QRMatrix memory qrMatrix,
        uint256 y,
        uint256 x,
        uint256 h,
        uint256 w,
        uint16[9] memory data
    ) internal pure returns (QRMatrix memory) {
        for (uint256 i = 0; i < h; ++i) {
            for (uint256 j = 0; j < w; ++j) {
                qrMatrix.matrix[y + i][x + j] = (data[i] >> j) & 1;
                qrMatrix.reserved[y + i][x + j] = 1;
            }
        }

        return qrMatrix;
    }

    function _putFormatInfo(QRMatrix memory _qrMatrix) internal pure {
        uint8[15] memory infoA = [
            0,
            1,
            2,
            3,
            4,
            5,
            7,
            8,
            22,
            23,
            24,
            25,
            26,
            27,
            28
        ];

        uint8[15] memory infoB = [
            28,
            27,
            26,
            25,
            24,
            23,
            22,
            21,
            7,
            5,
            4,
            3,
            2,
            1,
            0
        ];

        for (uint8 i = 0; i < 15; ++i) {
            uint8 r = infoA[i];
            uint8 c = infoB[i];
            _qrMatrix.matrix[r][8] = _qrMatrix.matrix[8][c] = (24144 >> i) & 1;
        }
    }

    function _putData(
        QRMatrix memory _qrMatrix,
        uint256[70] memory data
    ) internal pure returns (QRMatrix memory) {
        int256 n = 29;
        uint256 k = 0;
        int8 dir = -1;

        for (int256 i = n - 1; i >= 0; i = i - 2) {
            if (i == 6) {
                --i;
            } // skip the entire timing pattern column
            int256 jj = dir < 0 ? n - 1 : int256(0);
            for (int256 j = 0; j < n; j++) {
                for (int256 ii = int256(i); ii > int256(i) - 2; ii--) {
                    if (
                        _qrMatrix.reserved[uint256(jj)][uint256(ii)] == 0 &&
                        k >> 3 < 70
                    ) {
                        _qrMatrix.matrix[uint256(jj)][uint256(ii)] =
                            (data[k >> 3] >> (~k & 7)) &
                            1;
                        ++k;
                    }
                }

                if (dir == -1) {
                    jj = jj - 1;
                } else {
                    jj = jj + 1;
                }
            }

            dir = -dir;
        }

        return _qrMatrix;
    }

    function _generateQRURIByteVersion(
        QRMatrix memory _qrMatrix,
        string memory color
    ) internal pure returns (string memory) {
        bytes memory svgBytes = DynamicBuffer.allocate(1024 * 128);
        DynamicBuffer.appendSafe(
            svgBytes,
            abi.encodePacked(
                '<svg viewBox="0 0 300 300" width="500" height="500" xmlns="http://www.w3.org/2000/svg"><style>.bg{fill:#', // solhint-disable-line
                color,
                '}.fg{fill:#000}</style><rect class="bg" x="0" y="0" width="500" height="500"></rect>' // solhint-disable-line
            )
        );

        uint256 yo = 32;
        for (uint256 y = 0; y < 29; ++y) {
            uint256 xo = 32;
            for (uint256 x = 0; x < 29; ++x) {
                if (_qrMatrix.matrix[y][x] == 1) {
                    DynamicBuffer.appendSafe(
                        svgBytes,
                        abi.encodePacked(
                            '<rect x="', // solhint-disable-line
                            Strings.toString(xo),
                            '" y="', // solhint-disable-line
                            Strings.toString(yo),
                            '" class="fg" width="8" height="8"/>' // solhint-disable-line
                        )
                    );
                }
                xo += 8;
            }
            yo += 8;
        }

        DynamicBuffer.appendSafe(svgBytes, "</svg>");
        return string(svgBytes);
    }
}

