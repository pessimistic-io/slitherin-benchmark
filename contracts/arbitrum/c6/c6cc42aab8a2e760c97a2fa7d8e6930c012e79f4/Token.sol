// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { ERC20BaseInternal } from "./ERC20BaseInternal.sol";
import { SolidStateERC20 } from "./SolidStateERC20.sol";

import { IToken } from "./IToken.sol";
import { TokenInternal } from "./TokenInternal.sol";
import { AccrualData } from "./DataTypes.sol";

/// @title Token
/// @dev contains all externally called functions and necessary override for the Token facet contract
contract Token is TokenInternal, SolidStateERC20, IToken {
    /// @inheritdoc IToken
    function accrualData(
        address account
    ) external view returns (AccrualData memory data) {
        data = _accrualData(account);
    }

    /// @inheritdoc IToken
    function addMintingContract(address account) external onlyOwner {
        _addMintingContract(account);
    }

    /// @inheritdoc IToken
    function airdropSupply() external view returns (uint256 supply) {
        supply = _airdropSupply();
    }

    /// @notice overrides _beforeTokenTransfer hook to enforce non-transferability
    /// @param from sender of tokens
    /// @param to receiver of tokens
    /// @param amount quantity of tokens transferred
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20BaseInternal, TokenInternal) {
        super._beforeTokenTransfer(from, to, amount);
    }

    /// @inheritdoc IToken
    function BASIS() external pure returns (uint32 value) {
        value = _BASIS();
    }

    /// @inheritdoc IToken
    function burn(
        address account,
        uint256 amount
    ) external onlyMintingContract {
        _burn(amount, account);
    }

    /// @inheritdoc IToken
    function claim() external {
        _claim(msg.sender);
    }

    /// @inheritdoc IToken
    function claimableTokens(
        address account
    ) external view returns (uint256 amount) {
        amount = _claimableTokens(account);
    }

    /// @inheritdoc IToken
    function disperseTokens(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        _disperseTokens(recipients, amounts);
    }

    /// @inheritdoc IToken
    function distributionFractionBP()
        external
        view
        returns (uint32 fractionBP)
    {
        fractionBP = _distributionFractionBP();
    }

    /// @inheritdoc IToken
    function distributionSupply() external view returns (uint256 supply) {
        supply = _distributionSupply();
    }

    /// @inheritdoc IToken
    function globalRatio() external view returns (uint256 ratio) {
        ratio = _globalRatio();
    }

    /// @inheritdoc IToken
    function mint(
        address account,
        uint256 amount
    ) external onlyMintingContract {
        _mint(amount, account);
    }

    /// @inheritdoc IToken
    function mintAirdrop(uint256 amount) external onlyMintingContract {
        _mintAirdrop(amount);
    }

    /// @inheritdoc IToken
    function mintingContracts()
        external
        view
        returns (address[] memory contracts)
    {
        contracts = _mintingContracts();
    }

    /// @inheritdoc IToken
    function removeMintingContract(address account) external onlyOwner {
        _removeMintingContract(account);
    }

    /// @inheritdoc IToken
    function SCALE() external pure returns (uint256 value) {
        value = _SCALE();
    }

    /// @inheritdoc IToken
    function setDistributionFractionBP(
        uint32 _distributionFractionBP
    ) external onlyOwner {
        _setDistributionFractionBP(_distributionFractionBP);
    }
}

