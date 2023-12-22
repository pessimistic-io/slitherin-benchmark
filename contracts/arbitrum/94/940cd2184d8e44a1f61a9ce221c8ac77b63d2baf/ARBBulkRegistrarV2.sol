// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./IBulkRegistrar.sol";
import "./ARBRegistrarControllerV4.sol";
import "./ISidPriceOracle.sol";

contract ARBBulkRegistrarV2 is IBulkRegistrar {
    ARBRegistrarControllerV4 public immutable registrarController;

    constructor(ARBRegistrarControllerV4 _registrarController) {
        registrarController = _registrarController;
    }

    function bulkRentPrice(
        string[] calldata names,
        uint256 duration
    ) external view override returns (uint256 total) {
        for (uint256 i = 0; i < names.length; i++) {
            ISidPriceOracle.Price memory price = registrarController.rentPrice(
                names[i],
                duration
            );
            total += (price.base + price.premium);
        }
    }

    function bulkMakeCommitmentWithConfig(
        string[] calldata name,
        address owner,
        bytes32 secret,
        address resolver,
        address addr
    ) external view override returns (bytes32[] memory commitments) {
        commitments = new bytes32[](name.length);
        for (uint256 i = 0; i < name.length; i++) {
            commitments[i] = registrarController.makeCommitment(
                name[i],
                owner,
                secret
            );
        }
        return commitments;
    }

    function commitment(
        bytes32 commit
    ) external view override returns (uint256) {
        return registrarController.commitments(commit);
    }

    function bulkCommit(bytes32[] calldata commitments) external override {
        for (uint256 i = 0; i < commitments.length; i++) {
            registrarController.commit(commitments[i]);
        }
    }

    function bulkRegister(
        string[] calldata names,
        address owner,
        uint duration,
        bytes32 secret,
        address resolver,
        bool isUseGiftCard,
        bytes32 nodehash
    ) external payable {
        uint256 cost = 0;
        if (isUseGiftCard) {
            for (uint256 i = 0; i < names.length; i++) {
                ISidPriceOracle.Price memory price;
                price = registrarController.rentPrice(names[i], duration, owner);
                registrarController.registerWithConfigAndPoint{
                    value: (price.base + price.premium)
                }(names[i], owner, duration, secret, resolver, false, true);
                cost = cost + price.base + price.premium;
            }
        } else {
            for (uint256 i = 0; i < names.length; i++) {
                ISidPriceOracle.Price memory price;
                price = registrarController.rentPrice(names[i], duration);
                registrarController.registerWithConfigAndPoint{
                    value: (price.base + price.premium)
                }(names[i], owner, duration, secret, resolver, false, false);
                cost = cost + price.base + price.premium;
            }
        }
        // Send any excess funds back
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }
}

