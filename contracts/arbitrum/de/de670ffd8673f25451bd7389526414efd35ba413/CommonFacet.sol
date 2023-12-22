// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

import "./IMellowToken.sol";

import "./ICommonFacet.sol";

import "./CommonLibrary.sol";

contract CommonFacet is ICommonFacet {
    error Forbidden();

    bytes32 internal constant STORAGE_POSITION = keccak256("mellow.contracts.common.storage");

    function contractStorage() internal pure returns (ICommonFacet.Storage storage ds) {
        bytes32 position = STORAGE_POSITION;

        assembly {
            ds.slot := position
        }
    }

    function initializeCommonFacet(
        address[] memory immutableTokens_,
        address[] memory mutableTokens_,
        IOracle oracle_,
        string memory name,
        string memory symbol
    ) external override {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet.Storage storage ds = contractStorage();
        ds.immutableTokens = immutableTokens_;
        ds.mutableTokens = mutableTokens_;
        ds.tokens = CommonLibrary.merge(immutableTokens_, mutableTokens_);
        ds.oracle = oracle_;
        ds.lpToken = new LpToken(name, symbol, address(this));
    }

    function updateSecurityParams(
        IBaseOracle.SecurityParams[] calldata allTokensSecurityParams,
        IBaseOracle.SecurityParams[] calldata vaultTokensSecurityParams
    ) external {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet.Storage storage ds = contractStorage();
        ds.allTokensSecurityParams = abi.encode(allTokensSecurityParams);
        ds.vaultTokensSecurityParams = abi.encode(vaultTokensSecurityParams);
    }

    function updateMutableTokens(address[] memory newMutableTokens) external {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet.Storage storage ds = contractStorage();
        address[] memory mutableTokens = ds.mutableTokens;
        require(mutableTokens.length == newMutableTokens.length, "Invalid length");
        for (uint256 i = 0; i < mutableTokens.length; i++) {
            require(IMellowToken(mutableTokens[i]).isReplaceable(newMutableTokens[i]), "Non replaceable token");
        }
        ds.mutableTokens = newMutableTokens;
        ds.tokens = CommonLibrary.merge(ds.mutableTokens, ds.immutableTokens);
    }

    function updateOracle(IOracle newOracle) external override {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet.Storage storage ds = contractStorage();
        ds.oracle = newOracle;
    }

    function tvl() public view override returns (uint256) {
        ICommonFacet.Storage memory ds = contractStorage();
        address[] memory _tokens = ds.tokens;
        IOracle oracle_ = ds.oracle;

        uint256[] memory tokenAmounts = oracle_.getTokenAmounts(_tokens, ITokensManagementFacet(address(this)).vault());

        return
            oracle_.price(
                _tokens,
                tokenAmounts,
                abi.decode(ds.vaultTokensSecurityParams, (IBaseOracle.SecurityParams[])),
                abi.decode(ds.allTokensSecurityParams, (IBaseOracle.SecurityParams[]))
            );
    }

    function getValueOfTokens(
        address[] calldata _tokens,
        uint256[] calldata tokenAmounts
    ) public view override returns (uint256) {
        ICommonFacet.Storage memory ds = contractStorage();
        IOracle oracle_ = ds.oracle;
        return
            oracle_.price(
                _tokens,
                tokenAmounts,
                abi.decode(ds.vaultTokensSecurityParams, (IBaseOracle.SecurityParams[])),
                abi.decode(ds.allTokensSecurityParams, (IBaseOracle.SecurityParams[]))
            );
    }

    function tokens() public pure override returns (address[] memory, address[] memory, address[] memory) {
        ICommonFacet.Storage memory ds = contractStorage();
        return (ds.tokens, ds.immutableTokens, ds.mutableTokens);
    }

    function getTokenAmounts() public view override returns (address[] memory, uint256[] memory) {
        ICommonFacet.Storage memory ds = contractStorage();
        address[] memory tokens_ = ds.tokens;
        IOracle oracle_ = ds.oracle;

        uint256[] memory tokenAmounts = oracle_.getTokenAmounts(tokens_, ITokensManagementFacet(address(this)).vault());
        return (tokens_, tokenAmounts);
    }

    function lpToken() public pure override returns (LpToken) {
        ICommonFacet.Storage memory ds = contractStorage();
        return ds.lpToken;
    }

    function oracle() external pure override returns (IOracle) {
        ICommonFacet.Storage memory ds = contractStorage();
        return ds.oracle;
    }
}

