// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./WithReward.sol";
import {WithOwnership} from "./WithOwnership.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {IERC20Upgradeable} from "./ERC20_IERC20Upgradeable.sol";
import {Strings} from "./Strings.sol";
import "./ISwapRouterV2.sol";

contract Zkash is WithReward, WithOwnership, ERC20Upgradeable {
    using Strings for uint256;

    bool public isWhitelistedMode;

    modifier lockTheSwap() {
        _ds().processingFees = true;
        _;
        _ds().processingFees = false;
    }

    error MaxWallet(string message);

    event AddLiquidity(uint256 tokenAmount, uint256 ethAmount);

    function initialize(string memory _name, string memory _symbol) external initializer {
        LibDiamond.enforceIsContractOwner();

        __WithReward_init();
        __ERC20_init(_name, _symbol);
        _mint(_msgSender(), 50_000_000_000 * (10 ** 18));
        _grantRole(
            LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE,
            _ds().defaultRouter
        );
    }

    // ==================== Management ==================== //

    function setLiquidityWallet(
        address _liquidityWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().liquidityWallet = _liquidityWallet;
    }

    function setBuyFee(
        uint32 _liquidityBuyFee,
        uint32 _rewardBuyFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().fee.liquidityBuyFee = _liquidityBuyFee;
        _ds().fee.rewardBuyFee = _rewardBuyFee;
    }

    function setSellFee(
        uint32 _liquiditySellFee,
        uint32 _rewardSellFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().fee.liquiditySellFee = _liquiditySellFee;
        _ds().fee.rewardSellFee = _rewardSellFee;
    }

    function setIsLpPool(
        address _pairAddress,
        bool _isLp
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().lpPools[_pairAddress] = _isLp;
    }

    function setNumTokensToSwap(
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().numTokensToSwap = _amount;
    }

    function setProcessingGas(
        uint32 _gas
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().processingGas = _gas;
    }

    function setSwapRouter(
        address _routerAddress,
        bool _isRouter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().swapRouters[_routerAddress] = _isRouter;
    }

    function setDefaultRouter(
        address _router
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().defaultRouter = _router;
        _grantRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, _router);
    }

    function setDefaultAdminRole(
        address user
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEFAULT_ADMIN_ROLE, user);
    }

    function setImplementation(
        address _newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().methodsExposureFacetAddress = _newImplementation;
    }

    function setMaxTokenPerWallet(
        uint256 _maxTokenPerWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().maxTokenPerWallet = _maxTokenPerWallet;
    }

    function excludeFromFee(
        address _account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LibDiamond.EXCLUDED_FROM_FEE_ROLE, _account);
    }

    function excludeFromMaxWallet(
        address _account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, _account);
    }

    function setProcessRewards(
        bool _process
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().processRewards = _process;
    }

    function setProcessFeeRole(
        address _account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LibDiamond.PROCESS_FEE_ROLE, _account);
    }

    function setVestingContract(
        address _vestingContract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ds().vestingContract = _vestingContract;
    }

    function processFees() external onlyRole(LibDiamond.PROCESS_FEE_ROLE) {
        if (balanceOf(address(this)) >= _ds().numTokensToSwap) {
            _processFees(_ds().numTokensToSwap);
        }
    }

    function withdraw(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(this).balance >= _amount) {
            payable(msg.sender).transfer(_amount);
        }
    }

    // ==================== Views ==================== //

    function liquidityWallet() external view returns (address) {
        return _ds().liquidityWallet;
    }

    function buyFees() public view returns (uint256, uint256) {
        return (_ds().fee.liquidityBuyFee, _ds().fee.rewardBuyFee);
    }

    function sellFees() external view returns (uint256, uint256) {
        return (_ds().fee.liquiditySellFee, _ds().fee.rewardSellFee);
    }

    function defaultRouter() external view returns (address) {
        return _ds().defaultRouter;
    }

    function totalBuyFees() public view returns (uint32) {
        return _ds().fee.rewardBuyFee + _ds().fee.liquidityBuyFee;
    }

    function totalSellFees() public view returns (uint32) {
        return _ds().fee.rewardSellFee + _ds().fee.liquiditySellFee;
    }

    function numTokensToSwap() external view returns (uint256) {
        return _ds().numTokensToSwap;
    }

    function maxTokenPerWallet() external view returns (uint256) {
        return _ds().maxTokenPerWallet;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return hasRole(LibDiamond.EXCLUDED_FROM_FEE_ROLE, account);
    }

    function hasProcessFeeRole(address account) external view returns (bool) {
        return hasRole(LibDiamond.PROCESS_FEE_ROLE, account);
    }

    function isExcludedMaxWallet(address account) external view returns (bool) {
        return hasRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, account);
    }

    function isLpPool(address pairAddress) external view returns (bool) {
        return _ds().lpPools[pairAddress];
    }

    function isSwapRouter(address routerAddress) external view returns (bool) {
        return _ds().swapRouters[routerAddress];
    }

    function isProcessingRewards() external view returns (bool) {
        return _ds().processRewards;
    }

/* newly added for blacklist/whitelist */
    function isWhitelisted(address account) public view returns (bool) {
        return hasRole(LibDiamond.WHITELISTED_ROLE, account);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return hasRole(LibDiamond.BLACKLISTED_ROLE, account);
    }

    function setWhitelisted(
        address[] memory _accounts,
        bool set
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i;
        for (i = 0; i < _accounts.length; i ++) {
            if (hasRole(LibDiamond.WHITELISTED_ROLE, _accounts[i]) != set) {
                if (set) _grantRole(LibDiamond.WHITELISTED_ROLE, _accounts[i]);
                else _revokeRole(LibDiamond.WHITELISTED_ROLE, _accounts[i]);
            }
        }
    }

    function setBlacklisted(
        address[] memory _accounts,
        bool set
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i;
        for (i = 0; i < _accounts.length; i ++) {
            if (hasRole(LibDiamond.BLACKLISTED_ROLE, _accounts[i]) != set) {
                if (set) _grantRole(LibDiamond.BLACKLISTED_ROLE, _accounts[i]);
                else _revokeRole(LibDiamond.BLACKLISTED_ROLE, _accounts[i]);
            }
        }
    }

    function setWhitelistedMode(bool set) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isWhitelistedMode = set;
    }

/* newly added for role management */
    function setRoleByAdmin(
        address[] memory _accounts,
        bytes32 role,
        bool set
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i;
        for (i = 0; i < _accounts.length; i ++) {
            if (hasRole(role, _accounts[i]) != set) {
                if (set) _grantRole(role, _accounts[i]);
                else _revokeRole(role, _accounts[i]);
            }
        }
    }

    // =========== ERC20 =========== //

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (isWhitelistedMode) {
            require(isWhitelisted(from) || isWhitelisted(to), "Forbidden in whitelisted mode");
        } else {
            require(!isBlacklisted(from) && !isBlacklisted(to), "Blacklisted");
        }

        _checkMaxWallet(to, amount);

        bool processingFees = _ds().processingFees;
        (uint256 taxFee, bool isSell) = _determineFee(from, to);
        if (taxFee > 0) {
            uint256 taxAmount = amount /
                (LibDiamond.PERCENTAGE_DENOMINATOR + taxFee);
            taxAmount =
                amount -
                (taxAmount * LibDiamond.PERCENTAGE_DENOMINATOR);

            if (taxAmount > 0) {
                super._transfer(from, address(this), taxAmount);
            }

            uint256 sendAmount = amount - taxAmount;
            if (sendAmount > 0) {
                super._transfer(from, to, sendAmount);
            }
        } else {
            super._transfer(from, to, amount);
        }

        _setRewardBalance(from, balanceOf(from));
        _setRewardBalance(to, balanceOf(to));

        if (isSell && !processingFees && _ds().processRewards) {
            _processRewards();
        }
    }

    function _determineFee(
        address from,
        address to
    ) internal view returns (uint32, bool) {
        if (
            _ds().lpPools[to] &&
            !isExcludedFromFee(from) &&
            !isExcludedFromFee(to)
        ) {
            return (totalSellFees(), true);
        } else if (
            _ds().lpPools[from] &&
            !isExcludedFromFee(to) &&
            !_ds().swapRouters[to]
        ) {
            return (totalBuyFees(), false);
        }

        return (0, false);
    }

    function _processFees(uint256 tokenAmount) internal lockTheSwap {
        uint256 contractTokenBalance = balanceOf(address(this));
        uint32 totalTax = totalBuyFees();

        if (contractTokenBalance >= tokenAmount && totalTax > 0) {
            (uint256 liquidityBuyFee, uint256 rewardBuyFee) = buyFees();
            uint256 liquidityAmount = (tokenAmount * liquidityBuyFee) /
                totalTax;
            uint256 liquidityTokens = liquidityAmount / 2;
            uint256 rewardAmount = (tokenAmount * rewardBuyFee) / totalTax;
            uint256 liquidifyAmount = (liquidityAmount + rewardAmount) -
                liquidityTokens;

            // capture the contract's current balance.
            uint256 initialBalance = address(this).balance;

            // swap tokens
            if (liquidifyAmount > 0) {
                swapTokensForEth(liquidifyAmount);
            }

            // how much did we just swap into?
            uint256 newBalance = address(this).balance - initialBalance;

            // add liquidity
            uint256 liquidityETH = (newBalance * liquidityTokens) /
                liquidifyAmount;

            if (liquidityETH > 0) {
                _addLiquidity(liquidityTokens, liquidityETH);
            }

            accrueReward(newBalance - liquidityETH);
        }
    }

    function _checkMaxWallet(address recipient, uint256 amount) internal view {
        if (
            !hasRole(LibDiamond.EXCLUDED_FROM_MAX_WALLET_ROLE, recipient) &&
            balanceOf(recipient) + amount > _ds().maxTokenPerWallet
        ) revert MaxWallet("Max wallet exceeded");
    }

    // // =========== UNISWAP =========== //

    function swapTokensForEth(uint256 tokenAmount) internal {
        address router = _ds().defaultRouter;
        _approve(address(this), address(router), tokenAmount);

        // generate the swap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = ISwapRouterV2(router).WETH();

        bool[] memory stable = new bool[](2);
        stable[0] = false;
        stable[1] = false;

        // make the swap
        ISwapRouterV2(router)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 _value) internal {
        address router = _ds().defaultRouter;
        _approve(address(this), address(router), tokenAmount);
        ISwapRouterV2(router).addLiquidityETH{value: _value}(
            address(this),
            tokenAmount,
            0,
            0,
            _ds().liquidityWallet,
            block.timestamp
        );
        emit AddLiquidity(tokenAmount, _value);
    }
}

