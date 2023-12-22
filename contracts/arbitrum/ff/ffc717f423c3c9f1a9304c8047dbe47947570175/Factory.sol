// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Ownable} from "./Ownable.sol";
import {PerpieWallet} from "./Wallet.sol";
import {ProxyAdmin} from "./ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";
import "./console.sol";

/**
 * Factory of Perpie wallets
 */
contract PerpieFactory is Ownable {
    // ======= State ======= //
    address public latestImplementation;
    uint8 public version = 1;

    // ======= Admin ======= //
    function upgradeWalletVersion(
        address newImplementation
    ) external onlyOwner {
        version++;
        latestImplementation = newImplementation;
    }

    // ======= Methods ======= //
    /**
     * Deploy a Perpie Wallet
     * @param owner - The owner of the Perpie Wallet
     * @return wallet - The newly deployed wallet
     */
    function deploy(
        address owner
    ) external onlyOwner returns (PerpieWallet wallet) {
        /// Deploy proxy contract with latest impl contract,
        /// Assign self (factory) as admin temporarely
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            address(
                new TransparentUpgradeableProxy{
                    salt: bytes32(abi.encodePacked(owner))
                }(address(this), address(this), new bytes(0))
            )
        );

        proxy.upgradeToAndCall(
            latestImplementation,
            abi.encodeCall(PerpieWallet.initialize, (owner))
        );

        // Change admin to proxy itself - Making the wallet self-upgradeable (Verification wont happen
        // by looking at admin's msg.sender (it will be our executor so wont work), but rather not look at it
        // at all initially,
        proxy.changeAdmin(address(proxy));

        wallet = PerpieWallet(address(proxy));
    }

    // ======= View ======= //
    /**
     * Retreive wallet address based on owner
     * @param owner - Owner of the Perpie Wallet
     * @return wallet - The address of the wallet (computed)
     * @return isDeployed - Whether it's been deployed yet
     */
    function getWallet(
        address owner
    ) external view returns (PerpieWallet wallet, bool isDeployed) {
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(address(this), address(this), new bytes(0))
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                bytes32(abi.encodePacked(owner)),
                keccak256(bytecode)
            )
        );

        wallet = PerpieWallet(address(uint160(uint(hash))));
        isDeployed = address(wallet).code.length > 0;
    }

    receive() external payable {}
}

