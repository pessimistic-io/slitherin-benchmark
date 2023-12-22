// SPDX-License-Identifier: GPL-3.0
// inspired by https://github.com/ngmachado/Waterfall
pragma solidity 0.8.19;

import {MerkleProof} from "./MerkleProof.sol";
import {BitMaps} from "./BitMaps.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {ClonesUpgradeable} from "./ClonesUpgradeable.sol";
import {CommonError} from "./CommonError.sol";
import {Vault} from "./Vault.sol";
import {IWaterFall} from "./IWaterFall.sol";

contract WaterFall is SafeOwnableUpgradeable, UUPSUpgradeable, IWaterFall {
    using BitMaps for BitMaps.BitMap;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // @dev Config for the merkleRoot.
    mapping(bytes32 => Config) internal config;
    address public vaultImplementation;

    uint256[48] private _gap;

    function initialize(
        address owner_,
        address vaultImplementation_
    ) public initializer {
        if (owner_ == address(0) || vaultImplementation_ == address(0)) {
            revert CommonError.ZeroAddressSet();
        }
        vaultImplementation = vaultImplementation_;
        __Ownable_init(owner_);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setVaultImplementation(
        address vaultImplementation_
    ) external onlyOwner {
        vaultImplementation = vaultImplementation_;
    }

    // @dev IWaterfall.newDistribution implementation.
    function newDistribution(
        bytes32 merkleRoot,
        uint256 amount,
        address token,
        uint256 startTime,
        uint256 endTime
    ) external payable onlyOwner {
        require(
            config[merkleRoot].configured == false,
            "merkleRoot already register"
        );
        require(merkleRoot != bytes32(0), "empty root");
        require(startTime < endTime, "wrong dates");

        // initialize vault
        Vault vault = Vault(
            payable(ClonesUpgradeable.clone(vaultImplementation))
        );

        if (token == address(0)) {
            vault.initialize{value: amount}(address(this), token);
        } else {
            vault.initialize(address(this), token);
            IERC20Upgradeable(token).safeTransferFrom(
                msg.sender,
                address(vault),
                amount
            );
        }

        Config storage _config = config[merkleRoot];
        _config.token = IERC20Upgradeable(token);
        _config.tokensProvider = vault;
        _config.configured = true;
        _config.startTime = uint88(startTime);
        _config.endTime = uint96(endTime);
        emit NewDistribution(
            address(vault),
            token,
            merkleRoot,
            uint88(startTime),
            uint96(endTime)
        );
    }

    // @dev IWaterfall.isClaimed implementation.
    function isClaimed(
        bytes32 merkleRoot,
        address account
    ) public view returns (bool) {
        return config[merkleRoot].claimed.get(uint160(account));
    }

    // @dev Set index as claimed on specific merkleRoot
    function _setClaimed(bytes32 merkleRoot, address account) private {
        config[merkleRoot].claimed.set(uint160(account));
    }

    // @dev IWaterfall.claim implementation.
    function claim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(account, amount)))
        );

        bytes32 merkleRoot = MerkleProof.processProof(merkleProof, leaf);

        if (!config[merkleRoot].configured) {
            revert InvalidProof();
        }

        if (
            config[merkleRoot].startTime > block.timestamp ||
            config[merkleRoot].endTime < block.timestamp
        ) {
            revert InvalidClaimTime();
        }

        if (isClaimed(merkleRoot, account)) {
            revert AlreadyClaimed();
        }

        _setClaimed(merkleRoot, account);

        IERC20Upgradeable token = config[merkleRoot].token;
        Vault vault = config[merkleRoot].tokensProvider;

        if (address(token) == address(0)) {
            vault.rewardNative(account, amount);
        } else {
            vault.rewardERC20(account, amount);
        }

        emit Claimed(account, address(config[merkleRoot].token), amount);
    }

    /**
     * @dev withdraw remaining native tokens.
     */
    function withdraw(bytes32 root, address to) external onlyOwner {
        Vault vault = config[root].tokensProvider;
        vault.withdrawEmergency(to);
        emit Withdrawn(to);
    }
}

