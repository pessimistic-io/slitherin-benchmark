//    SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import "./SafeERC20.sol";

import { Router, FeeType } from "./Types.sol";

import "./Governable.sol";
import "./DiscountNft.sol";
import "./IFeeModule.sol";

abstract contract FeeModule is Governable, IFeeModule {
    address public protocolFeeVault;

    uint256 public nextProjectId;

    DiscountNft public feeDiscountNft;

    mapping(FeeType => uint256) public protocolFeeBps;
    mapping(uint256 => mapping(FeeType => uint256)) public projectFeeBps; // projectId -> FeeBps
    mapping(uint256 => address) public projectFeeVault; // projectId -> fee vault

    uint256 public constant MAX_FEE = 5000; // 5%, max project fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    /* ========= CONSTRUCTOR ========= */

    constructor(
        uint256[3] memory fees_,
        address governor_,
        address protocolFeeVault_,
        address feeDiscountNft_
    ) Governable(governor_) {
        require(protocolFeeVault_ != address(0) && feeDiscountNft_ != address(0), "DZF001");

        protocolFeeVault = protocolFeeVault_;
        feeDiscountNft = DiscountNft(feeDiscountNft_);

        protocolFeeBps[FeeType.BATCH_SWAP] = fees_[0];
        protocolFeeBps[FeeType.BATCH_SWAP_LP] = fees_[1];
        protocolFeeBps[FeeType.BATCH_TRANSFER] = fees_[2];
    }

    /* ========= RESTRICTED ========= */

    function updateProtocolFee(FeeType[] calldata feeTypes_, uint256[] calldata fees_) external onlyGovernance {
        for (uint256 i; i < feeTypes_.length; i++) {
            protocolFeeBps[feeTypes_[i]] = fees_[i];
        }

        emit ProtocolFeeUpdated();
    }

    function updateProtocolFeeVault(address newProtocolFeeVault_) external onlyGovernance {
        require(newProtocolFeeVault_ != address(0), "DZF001");

        protocolFeeVault = newProtocolFeeVault_;

        emit ProtocolFeeVaultUpdated();
    }

    function addProject(uint256[3] calldata fees_, address feeVault_) external onlyGovernance {
        require(feeVault_ != address(0), "DZF001");
        require(fees_[0] <= MAX_FEE && fees_[1] <= MAX_FEE && fees_[2] <= MAX_FEE, "DZF002");

        projectFeeBps[nextProjectId][FeeType.BATCH_SWAP] = fees_[0];
        projectFeeBps[nextProjectId][FeeType.BATCH_SWAP_LP] = fees_[1];
        projectFeeBps[nextProjectId][FeeType.BATCH_TRANSFER] = fees_[2];

        projectFeeVault[nextProjectId] = feeVault_;

        emit ProjectAdded(nextProjectId++);
    }

    // make fee vault 0
    function disableProject(uint256 projectId_) external onlyGovernance {
        require(projectId_ < nextProjectId, "DZF003");
        require(projectFeeVault[projectId_] != address(0), "DZF004");

        projectFeeVault[projectId_] = address(0);

        emit ProjectStatusDisabled(projectId_);
    }

    function updateProjectFee(
        uint256 projectId_,
        FeeType[] memory feeTypes_,
        uint256[] memory fees_
    ) external onlyGovernance {
        require(projectId_ < nextProjectId, "DZF003");

        for (uint256 i; i < feeTypes_.length; i++) {
            projectFeeBps[projectId_][feeTypes_[i]] = fees_[i];
        }

        emit ProjectFeeUpdated(projectId_);
    }

    // enable a disabled project
    // update vault
    function updateProjectFeeVault(uint256 projectId_, address feeVault_) external onlyGovernance {
        require(projectId_ < nextProjectId, "DZF003");
        require(feeVault_ != address(0), "DZF001");

        projectFeeVault[projectId_] = feeVault_;

        emit ProjectFeeVaultUpdated(projectId_);
    }

    /* ========= internal ========= */

    function _getFeeDetail(
        uint256 projectId_,
        uint256 nftId_,
        FeeType feeType_
    )
        internal
        view
        returns (
            uint256, // protocolFeeBps
            uint256, // projectFeeBps
            address // projectFeeVault
        )
    {
        require(projectId_ < nextProjectId && projectFeeVault[projectId_] != address(0), "DZF003");

        uint256 protocolFee = protocolFeeBps[feeType_];
        if (nftId_ == 0 || protocolFee == 0) {
            return (protocolFee, projectFeeBps[projectId_][feeType_], projectFeeVault[projectId_]);
        }

        require(feeDiscountNft.balanceOf(_msgSender(), nftId_) > 0, "DZF005");

        (uint256 discountedFeeBps, uint256 expiry) = feeDiscountNft.discountDetails(nftId_);

        if (block.timestamp < expiry) {
            protocolFee -= ((protocolFee * discountedFeeBps) / BPS_DENOMINATOR);
        }

        // require(block.timestamp < expiry, "Expired");
        // protocolFee -= ((protocolFee * discountedFeeBps) / BPS_DENOMINATOR);

        return (protocolFee, projectFeeBps[projectId_][feeType_], projectFeeVault[projectId_]);
    }

    function _calculateFeeAmount(
        uint256 amount_,
        uint256 protocolFeeBps_,
        uint256 projectFeeBps_
    )
        internal
        pure
        returns (
            uint256, // returnAmount
            uint256, // protocolFee
            uint256 // projectFee
        )
    {
        uint256 protocolFee = (amount_ * protocolFeeBps_) / BPS_DENOMINATOR;
        uint256 projectFee = (amount_ * projectFeeBps_) / BPS_DENOMINATOR;
        return (amount_ - (protocolFee + projectFee), protocolFee, projectFee);
    }
}
