// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IFundraisingRoundManager, IERC20} from "./IFundraisingRoundManager.sol";
import {ICapitalizationManager} from "./ICapitalizationManager.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {Upgradeable, Authority} from "./Upgradeable.sol";

import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";

import {EnumerableMap} from "./EnumerableMap.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC165} from "./IERC165.sol";
import {ERC165Checker} from "./ERC165Checker.sol";

/// @notice Facilitates fundraising round.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/StructuredCapitalRaise.sol)
contract StructuredCapitalRaise is IFundraisingRoundManager, Upgradeable, ERC165Upgradeable, AnnotatingMulticall {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    error StructuredCapitalRaise__NotCapitalizationManager(address account);
    error StructuredCapitalRaise__InsufficientAllowance();
    error StructuredCapitalRaise__ZeroAddress();

    event RoundAllowanceIncreased(address indexed shareToken, address indexed investor, uint256 amount);

    event RoundAllowanceDecreased(address indexed shareToken, address indexed investor, uint256 amount);

    event InvestmentReceived(address indexed shareToken, address indexed investor, uint256 funds);

    mapping(address => FundraisingRoundData) private _fundraisingRoundData;

    mapping(address => ICapitalizationManager) private capitalizationManager;

    /// @dev Per investor allowance for contributing funds to round
    mapping(address => EnumerableMap.AddressToUintMap) private roundAllowance;

    function name() external pure override returns (string memory) {
        return 'StructuredCapitalRaise';
    }

    /**
     * @notice Initialize structured capital raise and base contracts.
     * @dev This function can only be called once.
     */
    function initialize() external initializer {
        __Upgradeable_init(msg.sender, Authority(address(0)));
    }

    function fundraisingRoundData(address shareToken) external view returns (FundraisingRoundData memory) {
        return _fundraisingRoundData[shareToken];
    }

    /// @inheritdoc IFundraisingRoundManager
    function createRound(address shareToken, FundraisingRoundData calldata roundData) external override whenNotPaused {
        if (address(_fundraisingRoundData[shareToken].fundingToken) != address(0))
            revert FundraisingRoundManager__Active();
        if (address(roundData.fundingToken) == address(0)) revert StructuredCapitalRaise__ZeroAddress();
        if (roundData.payableTo == address(0)) revert StructuredCapitalRaise__ZeroAddress();
        if (roundData.manager == address(0)) revert StructuredCapitalRaise__ZeroAddress();
        if (!ERC165Checker.supportsInterface(msg.sender, type(ICapitalizationManager).interfaceId))
            revert FundraisingRoundManager__InvalidCapitalizationManager(msg.sender);

        _fundraisingRoundData[shareToken] = roundData;
        capitalizationManager[shareToken] = ICapitalizationManager(msg.sender);
    }

    /// @notice Currently approved maximum investment amount
    function getRoundAllowance(address shareToken, address investor) public view returns (uint256) {
        (, uint256 allowance) = roundAllowance[shareToken].tryGet(investor);
        return allowance;
    }

    /**
     * @notice Increase how much an investor can contribute to round
     * @dev Only callable by round's deal maker
     */
    function increaseRoundAllowance(
        address shareToken,
        address investor,
        uint256 amount
    ) external {
        if (msg.sender != _fundraisingRoundData[shareToken].manager) revert FundraisingRoundManager__NotManager();

        emit RoundAllowanceIncreased(shareToken, investor, amount);

        // slither-disable-next-line unused-return
        roundAllowance[shareToken].set(investor, getRoundAllowance(shareToken, investor) + amount);
    }

    /**
     * @notice Decrease how much an investor can contribute to round
     * @dev Only callable by round's deal maker
     */
    function decreaseRoundAllowance(
        address shareToken,
        address investor,
        uint256 amount
    ) external {
        if (msg.sender != _fundraisingRoundData[shareToken].manager) revert FundraisingRoundManager__NotManager();

        emit RoundAllowanceDecreased(shareToken, investor, amount);

        _setOrRemoveAllowance(shareToken, investor, getRoundAllowance(shareToken, investor) - amount);
    }

    function _setOrRemoveAllowance(
        address shareToken,
        address investor,
        uint256 amount
    ) private {
        if (amount == 0) {
            // slither-disable-next-line unused-return
            roundAllowance[shareToken].remove(investor);
        } else {
            // slither-disable-next-line unused-return
            roundAllowance[shareToken].set(investor, amount);
        }
    }

    /**
     * @notice Contribute to round and receive shares
     * @dev Callable by any investor with allowance
     */
    function invest(address shareToken, uint256 funds) external override whenNotPaused returns (uint256) {
        uint256 allowance = getRoundAllowance(shareToken, msg.sender);
        if (funds > allowance) revert StructuredCapitalRaise__InsufficientAllowance();

        // Decrease allowance by incoming funds
        _setOrRemoveAllowance(shareToken, msg.sender, allowance - funds);

        emit InvestmentReceived(shareToken, msg.sender, funds);

        // Transfer payment from caller
        _fundraisingRoundData[shareToken].fundingToken.safeTransferFrom(
            msg.sender,
            _fundraisingRoundData[shareToken].payableTo,
            funds
        );

        // Call capmgr to issue
        return capitalizationManager[shareToken].issueForRound(shareToken, msg.sender, funds);
    }

    function close(address shareToken) external override {
        if (msg.sender != address(capitalizationManager[shareToken]))
            revert StructuredCapitalRaise__NotCapitalizationManager(msg.sender);

        // Close open allowances
        EnumerableMap.AddressToUintMap storage allowances = roundAllowance[shareToken];
        for (uint i = 0; i < allowances.length(); i++) {
            (address investor, ) = allowances.at(i);
            // slither-disable-next-line unused-return
            allowances.remove(investor);
        }

        delete _fundraisingRoundData[shareToken];
        delete capitalizationManager[shareToken];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IFundraisingRoundManager).interfaceId || super.supportsInterface(interfaceId);
    }
}

