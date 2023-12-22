// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

contract Tiny1155NTT {
    string public name;
    string public symbol;
    string internal baseTokenURI;
    uint256 public totalSupply;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    function balanceOfBatch(address[] memory owners, uint256[] memory ids)
        public
        view
        virtual
        returns (uint256[] memory balances)
    {
        uint256 ownersLength = owners.length; // Saves MLOADs.

        require(ownersLength == ids.length, "LENGTH_MISMATCH");

        balances = new uint256[](ownersLength);

        unchecked {
            for (uint256 i = 0; i < ownersLength; ++i) {
                balances[i] = balanceOf[owners[i]][ids[i]];
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
            interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
    }

    function _mint(
        address to,
        uint256 id,
        uint256 amount
    ) internal // bytes memory data
    {
        balanceOf[to][id] += amount;

        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    function _setBaseTokenURI(string memory uri_) internal virtual {
        baseTokenURI = uri_;
    }

    function _toString(uint256 value_) internal pure returns (string memory) {
        if (value_ == 0) {
            return "0";
        }
        uint256 _iterate = value_;
        uint256 _digits;
        while (_iterate != 0) {
            _digits++;
            _iterate /= 10;
        } // get digits in value_
        bytes memory _buffer = new bytes(_digits);
        while (value_ != 0) {
            _digits--;
            _buffer[_digits] = bytes1(uint8(48 + uint256(value_ % 10)));
            value_ /= 10;
        } // create bytes of value_
        return string(_buffer); // return string converted bytes of value_
    }
}

