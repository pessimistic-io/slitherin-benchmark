// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IArbERC721.sol";
import "./1-1-OpenBloxL1.sol";

contract OpenBloxL2 is OpenBloxL1, IArbERC721 {
    address public l2Gateway;
    address public override l1Address;

    function initialize(address _l2Gateway, address _l1TokenAddress) public virtual initializer {
        __ERC721Preset_init("OpenBlox", "BLOX", "https://metadata.openblox.io/nft/");

        l2Gateway = _l2Gateway;
        l1Address = _l1TokenAddress;
    }

    function getChainId() public view virtual returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    modifier onlyL2Gateway() {
        require(msg.sender == l2Gateway, "OpenBlox: not gateway");
        _;
    }

    function bridgeMint(
        address account,
        uint256 amount,
        bytes calldata data
    ) external virtual override onlyL2Gateway {
        bytes[] memory bloxesFromL1 = _decodeL1BloxesData(amount, data);
        for (uint256 i = 0; i < amount; ++i) {
            (uint256 tokenId, uint256 genes, uint256 bornAt, uint16 generation, uint256 parent0Id, uint256 parent1Id, uint256 ancestorCode, uint8 reproduction) = abi.decode(
                bloxesFromL1[i],
                (uint256, uint256, uint256, uint16, uint256, uint256, uint256, uint8)
            );
            _mintBlox(tokenId, account, genes, bornAt, generation, parent0Id, parent1Id, ancestorCode, reproduction);
        }
    }

    function _decodeL1BloxesData(uint256 amount, bytes calldata data) internal pure virtual returns (bytes[] memory) {
        bytes[] memory bloxesFromL1 = new bytes[](amount);
        for (uint256 i = 0; i < amount; ++i) {
            bloxesFromL1[i] = data[i * 256:(i + 1) * 256];
        }
        return bloxesFromL1;
    }
}

