//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

// Core utils used extensively to format CSS and numbers.
library utils {
    // used to simulate empty strings
    string internal constant NULL = "";

    function rgbaString(string memory _rgb, string memory _a)
        internal
        pure
        returns (string memory)
    {
        string memory formattedA = stringsEqual(_a, "100")
            ? "1"
            : string.concat("0.", _a);

        return string.concat("rgba(", _rgb, ",", formattedA, ")");
    }

    // formats generic rgba color in css
    function rgba(
        uint256 _r,
        uint256 _g,
        uint256 _b,
        string memory _a
    ) internal pure returns (string memory) {
        string memory formattedA = stringsEqual(_a, "100")
            ? "1"
            : string.concat("0.", _a);

        return
            string.concat(
                "rgba(",
                utils.uint2str(_r),
                ",",
                utils.uint2str(_g),
                ",",
                utils.uint2str(_b),
                ",",
                formattedA,
                ")"
            );
    }

    function rgbaFromArray(uint256[3] memory _arr, string memory _a)
        internal
        pure
        returns (string memory)
    {
        return rgba(_arr[0], _arr[1], _arr[2], _a);
    }

    // checks if two strings are equal
    function stringsEqual(string memory _a, string memory _b)
        internal
        pure
        returns (bool)
    {
        return
            keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    // converts an unsigned integer to a string
    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // get a random integer in a range of ints
    function getRandomInteger(
        string memory _name,
        uint256 _seed,
        uint256 _min,
        uint256 _max
    ) internal pure returns (uint256) {
        if (_max <= _min) return _min;
        return
            (uint256(keccak256(abi.encodePacked(_name, _seed))) %
                (_max - _min)) + _min;
    }

    // suffle an array of uints
    function shuffle(uint256[3] memory _arr, uint256 _seed)
        internal
        view
        returns (uint256[3] memory)
    {
        for (uint256 i = 0; i < _arr.length; i++) {
            uint256 n = i +
                (uint256(keccak256(abi.encodePacked(block.timestamp, _seed))) %
                    (_arr.length - i));
            uint256 temp = _arr[n];
            _arr[n] = _arr[i];
            _arr[i] = temp;
        }

        return _arr;
    }
}

