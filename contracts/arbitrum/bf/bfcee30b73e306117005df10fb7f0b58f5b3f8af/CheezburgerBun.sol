// SPDX-License-Identifier: MIT
// This contract was deployed using the Cheezburger Factory.
// You can check the tokenomics, website and social from the public read functions.
pragma solidity ^0.8.22;

import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {CheezburgerDynamicTokenomics} from "./CheezburgerDynamicTokenomics.sol";
import {ICheezburgerFactory} from "./ICheezburgerFactory.sol";

contract CheezburgerBun is CheezburgerDynamicTokenomics, ERC20 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error TransferToZeroAddress(address from, address to);
    error TransferToToken(address to);
    error TransferMaxTokensPerWallet();
    error OnlyOneBuyPerBlockAllowed();
    error CannotReceiveEtherDirectly();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event LiquiditySwapSuccess(bool success);
    event LiquiditySwapFailed(string reason);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    string public FACTORY_VERSION = "Cheddar (1.1)";
    string private _name;
    string private _symbol;
    string private _website;
    string private _social;
    address public constant owner = address(0);
    mapping(address => uint256) private _holderLastBuyTimestamp;

    ICheezburgerFactory public immutable factory =
        ICheezburgerFactory(msg.sender);
    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    uint8 internal isSwapping = 1;

    constructor(
        TokenCustomization memory _customization,
        DynamicSettings memory _fees,
        DynamicSettings memory _wallet
    ) CheezburgerDynamicTokenomics(_fees, _wallet) {
        _name = _customization.name;
        _symbol = _customization.symbol;
        _website = _customization.website;
        _social = _customization.social;
        _mint(address(factory), _customization.supply * (10 ** decimals()));
    }

    /// @dev Prevents direct Ether transfers to contract
    receive() external payable {
        revert CannotReceiveEtherDirectly();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC20 METADATA                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function website() public view returns (string memory) {
        return _website;
    }

    function social() public view returns (string memory) {
        return _social;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (to == address(this)) {
            revert TransferToToken(to);
        }

        // Cache pair internally if available
        if (address(pair) == address(0) || address(router) == address(0)) {
            if (address(factory).code.length > 0) {
                (IUniswapV2Router02 _router, IUniswapV2Pair _pair) = factory
                    .burgerRegistryRouterOnly(address(this));
                pair = _pair;
                router = _router;
            }
        }

        bool isBuying = from == address(pair);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                        LIQUIDITY SWAP                      */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        if (
            !isBuying &&
            isSwapping == 1 &&
            balanceOf(address(factory)) > 0 &&
            address(pair) != address(0) &&
            pair.totalSupply() > 0 &&
            from != address(router) &&
            to != address(router)
        ) {
            doLiquiditySwap();
        }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);

        // Must use burn() to burn tokens
        if (to == address(0) && balanceOf(address(0)) > 0) {
            revert TransferToZeroAddress(from, to);
        }

        // Don't look after self transfers
        if (from == to) {
            return;
        }

        // Ignore Factory-related txs
        if (to == address(factory) || from == address(factory)) {
            return;
        }

        bool isBuying = from == address(pair);
        bool isSelling = to == address(pair);
        DynamicTokenomicsStruct memory tokenomics = _getTokenomics(
            totalSupply()
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                          TXS LIMITS                        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (isBuying) {
            bool buyFeeStillDecreasing = tokenomics.earlyAccessPremium !=
                tokenomics.sellFee;
            if (buyFeeStillDecreasing) {
                if (_holderLastBuyTimestamp[tx.origin] == block.number) {
                    revert OnlyOneBuyPerBlockAllowed();
                }
                _holderLastBuyTimestamp[tx.origin] = block.number;
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                            FEES                            */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        uint256 feeAmount = 0;
        if (isBuying || isSelling) {
            unchecked {
                if (isBuying && tokenomics.earlyAccessPremium > 0) {
                    feeAmount = amount * tokenomics.earlyAccessPremium;
                } else if (isSelling && tokenomics.sellFee > 0) {
                    feeAmount = amount * tokenomics.sellFee;
                }
                if (feeAmount > 0) {
                    super._transfer(to, address(factory), feeAmount / 10000);
                    emit AppliedTokenomics(tokenomics);
                }
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                        WALLET LIMITS                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (!isSelling) {
            unchecked {
                bool walletExceedLimits = balanceOf(to) >
                    tokenomics.maxTokensPerWallet;
                if (walletExceedLimits) {
                    revert TransferMaxTokensPerWallet();
                }
            }
        }
    }

    function doLiquiditySwap() private lockSwap {
        try factory.beforeTokenTransfer(balanceOf(address(factory))) returns (
            bool result
        ) {
            emit LiquiditySwapSuccess(result);
        } catch Error(string memory reason) {
            emit LiquiditySwapFailed(reason);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// Burns tokens from the caller.
    ///
    /// @dev Burns `amount` tokens from the caller.
    ///
    /// See {ERC20-_burn}.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// Burns tokens from an account's allowance.
    ///
    /// @dev Burns `amount` tokens from `account`, deducting from the caller's
    /// allowance.
    ///
    /// See {ERC20-_burn} and {ERC20-allowance}.
    ///
    /// Requirements:
    ///
    /// - the caller must have allowance for ``accounts``'s tokens of at least
    /// `amount`.
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Get current dynamic tokenomics
    /// @return DynamicTokenomics struct with current values
    /// @notice Values will change dynamically based on configured durations and percentages
    function getTokenomics()
        external
        view
        returns (DynamicTokenomicsStruct memory)
    {
        return _getTokenomics(totalSupply());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier lockSwap() {
        isSwapping = 2;
        _;
        isSwapping = 1;
    }
}

