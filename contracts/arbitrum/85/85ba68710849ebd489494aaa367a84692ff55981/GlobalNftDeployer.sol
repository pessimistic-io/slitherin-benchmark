// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Strings.sol";
import "./IERC1155.sol";

import "./Consts.sol";
import "./GlobalNftERC721.sol";
import { GlobalERC1155 } from "./GlobalERC1155.sol";
import "./IGlobalNftDeployer.sol";
import "./BeaconProxy.sol";
import "./Types.sol";

contract GlobalNftDeployer is IGlobalNftDeployer {
    using Types for address;
    using Strings for uint256;
    address beacon721;
    address beacon1155;
    mapping(address => bool) public override isGlobalNft;

    function calcAddr(uint64 originChain, address originAddr) public view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                address(this),
                                keccak256(abi.encode(originChain, originAddr)),
                                Consts.BEACON_PROXY_CODE_HASH
                            )
                        )
                    )
                )
            );
    }

    function _mint(
        uint64 originChain,
        bool isERC1155,
        address originAddr,
        uint256 tokenId,
        address recipient
    ) internal {
        address nft = calcAddr(originChain, originAddr);
        bool exist;
        assembly {
            exist := gt(extcodesize(nft), 0)
        }
        if (!exist) {
            BeaconProxy proxy = new BeaconProxy{ salt: keccak256(abi.encode(originChain, originAddr)) }();
            address beacon = isERC1155 ? beacon1155 : beacon721;
            proxy.initializeBeacon(beacon, "");
            IGlobalNft(address(proxy)).initialize(address(this), originChain, isERC1155, originAddr);
            isGlobalNft[address(proxy)] = true;
        }
        if (isERC1155) {
            GlobalERC1155(nft).mint(recipient, tokenId, 1, "");
        } else {
            GlobalNftERC721(nft).mint(recipient, tokenId);
        }
        emit GlobalNftMinted(originChain, isERC1155, originAddr, tokenId, address(nft));
    }

    function _burn(address from, uint64 originChain, address originAddr, uint256 tokenId) internal {
        address nft = calcAddr(originChain, originAddr);
        bool exist;
        assembly {
            exist := gt(extcodesize(nft), 0)
        }
        require(exist, "not exist");
        if (IGlobalNft(nft).originIsERC1155()) {
            GlobalERC1155(nft).burn(from, tokenId, 1);
        } else {
            GlobalNftERC721(nft).burn(tokenId);
        }
        emit GlobalNftBurned(originChain, IGlobalNft(nft).originIsERC1155(), originAddr, tokenId, address(nft));
    }

    /// @notice only serve the nft appeared in hunt game
    function tokenURI(address globalNft, uint256 tokenId) public view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "https://backend.huntnft.org/assets/",
                    uint256(GlobalNftERC721(globalNft).originChain()).toString(),
                    "/",
                    globalNft.toHex(),
                    "/",
                    tokenId.toString()
                )
            );
    }
}

