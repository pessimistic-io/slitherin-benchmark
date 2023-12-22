// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BeaconProxy.sol";
import "./IHuntGameDeployer.sol";
import "./HuntGame.sol";
import "./Consts.sol";

/**huntnft
 * @title HunterPoolDeployer depoly hunter pool with provided params
 * @notice every unique paymentToken, nft , bulletPrice will create a unique pool
 */
contract HuntGameDeployer is IHuntGameDeployer {
    address beacon;
    /// @dev used to make game address unique
    mapping(address => uint256) public userNonce;
    struct DeployParams {
        IHunterValidator hunterValidator;
        IHuntGame.NFTStandard nftStandard;
        uint64 totalBullets;
        uint256 bulletPrice;
        address nftContract;
        uint64 originChain;
        address getPayment;
        IHuntNFTFactory factory;
        uint256 tokenId;
        uint64 gameId;
        uint64 ddl;
        address owner;
    }

    function calcGameAddr(address creator, uint256 nonce) public view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                address(this),
                                keccak256(abi.encode(creator, nonce)),
                                Consts.BEACON_PROXY_CODE_HASH
                            )
                        )
                    )
                )
            );
    }

    function getPendingGame(address creator) public view returns (address) {
        return calcGameAddr(creator, userNonce[creator]);
    }

    function _deploy(DeployParams storage tempDeployParams) internal returns (address game) {
        BeaconProxy proxy = new BeaconProxy{ salt: keccak256(abi.encode(msg.sender, userNonce[msg.sender])) }();
        proxy.initializeBeacon(beacon, "");
        game = address(proxy);
        HuntGame(game).initialize(
            tempDeployParams.hunterValidator,
            tempDeployParams.nftStandard,
            tempDeployParams.totalBullets,
            tempDeployParams.bulletPrice,
            tempDeployParams.nftContract,
            tempDeployParams.originChain,
            tempDeployParams.getPayment,
            tempDeployParams.factory,
            tempDeployParams.tokenId,
            tempDeployParams.gameId,
            tempDeployParams.ddl,
            tempDeployParams.owner
        );
        userNonce[msg.sender]++;
    }
}

