// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Clone.sol";
import "./ILBToken.sol";
import "./ILBPair.sol";
import "./TokenHelper.sol";
import "./LiquidityAmounts.sol";

import "./ISPVault.sol";
import "./ISPVFactory.sol";

/**
 * @title Liquidity Book Vault For Single Pair
 * @author Trader Joe
 * @notice This contract is used to interact with the Liquidity Book Pair contract.
 * Any tokens sent to this contract will be owned by the owner of this contract.
 */
contract SPVault is Clone, ISPVault {
    using TokenHelper for IERC20;
    using LiquidityAmounts for address;

    uint256 private constant PRECISION = 1e18;

    uint256 private constant _MASK_EDGE = 0xffffff;
    uint256 private constant _MASK_RANGE = 0xffffffffffff;
    uint256 private constant _MASK_MANAGER = 0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000;

    uint256 private constant _SHIFT_UPPER = 24;
    uint256 private constant _SHIFT_MANAGER = 96;

    bytes32 private _parameters;

    ISPVFactory private immutable _factory;

    constructor(ISPVFactory factory) {
        _factory = factory;
    }

    /**
     * @notice Returns the address of the pair
     * @return The address of the pair
     */
    function getPair() public view virtual override returns (ILBPair) {
        return _pair();
    }

    /**
     * @notice Returns the address of the token X
     * @return The address of the token X
     */
    function getTokenX() public view virtual override returns (IERC20) {
        return _tokenX();
    }

    /**
     * @notice Returns the address of the token Y
     * @return The address of the token Y
     */
    function getTokenY() public view virtual override returns (IERC20) {
        return _tokenY();
    }

    /**
     * @notice Returns the range of the vault.
     * @dev The range is the range of bins where the vault has liquidity.
     * @return low The low end of the range.
     * @return upper The upper end of the range.
     */
    function getRange() public view virtual override returns (uint24 low, uint24 upper) {
        (low, upper) = _decodeRange(_parameters);
    }

    /**
     * @notice Returns the manager of the vault.
     * @return The manager of the vault.
     */
    function getManager() public view virtual override returns (address) {
        return _decodeManager(_parameters);
    }

    /**
     * @notice Returns the factory
     * @return The factory
     */
    function getFactory() public view virtual override returns (ISPVFactory) {
        return _factory;
    }

    /**
     * @notice Returns the Fees that can be collected from the vault for each pair.
     * @return amountX The amount of token X that can be collected.
     * @return amountY The amount of token Y that can be collected.
     */
    function getCollectableFees() public view virtual override returns (uint256 amountX, uint256 amountY) {
        (uint24 low, uint24 upper) = _decodeRange(_parameters);

        uint256[] memory ids = _getIds(low, upper);

        (amountX, amountY) = _pair().pendingFees(address(this), ids);
    }

    /**
     * @notice Previews the amounts of token X and Y that will be received when withdrawing.
     * @param removedLow The low end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @return amountX The amount of token X that will be received.
     * @return amountY The amount of token Y that will be received.
     */
    function previewWithdraw(uint24 removedLow, uint24 removedUpper)
        public
        view
        virtual
        override
        returns (uint256 amountX, uint256 amountY)
    {
        (uint24 previousLow, uint24 previousUpper) = _decodeRange(_parameters);

        if (removedUpper < removedLow || removedUpper < previousLow || removedLow > previousUpper) {
            return (0, 0);
        }

        uint24 low = previousLow > removedLow ? previousLow : removedLow;
        uint24 upper = previousUpper < removedUpper ? previousUpper : removedUpper;

        uint256[] memory ids = _getIds(low, upper);

        (amountX, amountY) = LiquidityAmounts.getAmountsOf(address(this), ids, address(_pair()));
    }

    /**
     * @notice Deposits tokens of the vault to the pair.
     * @dev The range will be expanded to include the added range.
     * The added range must not overlap, but connect with the existing range or it needs to be inside.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     * @param addedLow The low end of the range to add.
     * @param addedUpper The upper end of the range to add.
     */
    function deposit(uint256 amountX, uint256 amountY, uint24 addedLow, uint24 addedUpper) public virtual override {
        bytes32 parameters = _parameters;
        _onlyManager(parameters);

        _parameters = _expand(parameters, addedLow, addedUpper);

        uint256 delta = addedUpper - addedLow + 1;

        uint256[] memory ids = new uint256[](delta);
        uint256[] memory distributionX = new uint256[](delta);
        uint256[] memory distributionY = new uint256[](delta);

        (,, uint256 activeId) = _pair().getReservesAndId();

        uint256 binsX = addedUpper < activeId ? 0 : addedUpper + 1 - _max(addedLow, activeId);
        uint256 binsY = addedLow > activeId ? 0 : _min(addedUpper, activeId) + 1 - addedLow;

        for (uint256 i; i < delta;) {
            uint256 id = addedLow + i;
            ids[i] = id;

            if (id >= activeId) {
                distributionX[i] = PRECISION / binsX;
            }
            if (id <= activeId) {
                distributionY[i] = PRECISION / binsY;
            }

            unchecked {
                ++i;
            }
        }

        _tokenX().safeTransfer(address(_pair()), amountX);
        _tokenY().safeTransfer(address(_pair()), amountY);

        _pair().mint(ids, distributionX, distributionY, address(this));

        emit Deposited(_pair(), amountX, amountY, addedLow, addedUpper);
    }

    /**
     * @notice Withdraws tokens of the vault from the pair.
     * @dev The range will be shrunk to exclude the removed range.
     * The removed range must be inside the existing range and contains at least one of the edges of the existing range.
     * @param removedLow The low end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     */
    function withdraw(uint24 removedLow, uint24 removedUpper) public virtual override {
        bytes32 parameters = _parameters;
        _onlyManager(parameters);

        _parameters = _shrink(parameters, removedLow, removedUpper);

        _withdraw(address(_pair()), removedLow, removedUpper);

        _collectFees(parameters);

        emit Withdrawn(_pair(), removedLow, removedUpper);
    }

    /**
     * @notice Collects fees from the pair.
     */
    function collectFees() public virtual override {
        bytes32 parameters = _parameters;

        _onlyManager(parameters);
        _collectFees(parameters);
    }

    /**
     */

    /**
     * @notice Executes a call to a target contract.
     * @param target The address of the target contract.
     * @param amount The amount of ETH to send.
     * @param data The data to send.
     */
    function execute(address target, uint256 amount, bytes memory data) public virtual override {
        _onlyManager(_parameters);

        (bool success,) = target.call{value: amount}(data);
        require(success, "MSVault: call failed");
    }

    /**
     * @notice Set the manager of the vault
     * @param manager The address of the manager
     */
    function setManager(address manager) external {
        bytes32 parameters = _parameters;
        _onlyManager(parameters);

        _parameters = _encodeManager(parameters, manager);
    }

    /**
     * @dev Checks if the msg.sender is the manager or the owner.
     * @param parameters The current encoded parameters
     */
    function _onlyManager(bytes32 parameters) internal view {
        address manager = _decodeManager(parameters);
        require(msg.sender == manager || msg.sender == _factory.getDefaultManager(), "MSVault: unauthorized");
    }

    /**
     * @dev Returns the address of the pair.
     * @return pair The address of the pair.
     */
    function _pair() internal view virtual returns (ILBPair pair) {
        pair = ILBPair(_getArgAddress(0));
    }

    /**
     * @dev Returns the address of the token X.
     * @return tokenX The address of the token X.
     */
    function _tokenX() internal view virtual returns (IERC20 tokenX) {
        tokenX = IERC20(_getArgAddress(20));
    }

    /**
     * @dev Returns the address of the token Y.
     * @return tokenY The address of the token Y.
     */
    function _tokenY() internal view virtual returns (IERC20 tokenY) {
        tokenY = IERC20(_getArgAddress(40));
    }

    /**
     * @dev Encodes the range.
     * @param parameters The current encoded parameters
     * @param low The low end of the range.
     * @param upper The upper end of the range.
     * @return newParameters The encoded range.
     */
    function _encodeRange(bytes32 parameters, uint24 low, uint24 upper) internal pure returns (bytes32 newParameters) {
        require(low <= upper, "MSVault: invalid range");

        assembly {
            newParameters := and(parameters, not(_MASK_RANGE))
            newParameters := or(newParameters, or(low, shl(_SHIFT_UPPER, upper)))
        }
    }

    /**
     * @dev Encodes the manager.
     * @param parameters The current encoded parameters
     * @param manager The address of the manager.
     * @return newParameters The encoded parameters.
     */
    function _encodeManager(bytes32 parameters, address manager) internal pure returns (bytes32 newParameters) {
        assembly {
            newParameters := and(parameters, not(_MASK_MANAGER))
            newParameters := or(newParameters, shl(_SHIFT_MANAGER, manager))
        }
    }

    /**
     * @dev Decodes the range.
     * @param parameters The encoded parameters.
     * @return low The low end of the range.
     * @return upper The upper end of the range.
     */
    function _decodeRange(bytes32 parameters) internal pure returns (uint24 low, uint24 upper) {
        assembly {
            low := and(parameters, _MASK_EDGE)
            upper := and(shr(_SHIFT_UPPER, parameters), _MASK_EDGE)
        }
    }

    /**
     * @dev Decodes the manager.
     * @param parameters The encoded parameters.
     * @return manager The address of the manager.
     */
    function _decodeManager(bytes32 parameters) internal pure returns (address manager) {
        assembly {
            manager := shr(_SHIFT_MANAGER, parameters)
        }
    }

    /**
     * @dev Expands the range. The range will be expanded to include the added range.
     * The added range must be outside the existing range and adjacent to the existing range.
     * If the new range is completely inside the existing range, the existing range will be returned.
     * @param parameters The current encoded parameters.
     * @param addedLow The low end of the range to add.
     * @param addedUpper The upper end of the range to add.
     * @return The new encoded range.
     */
    function _expand(bytes32 parameters, uint24 addedLow, uint24 addedUpper) internal pure returns (bytes32) {
        (uint24 previousLow, uint24 previousUpper) = _decodeRange(parameters);
        if (previousUpper == 0) return _encodeRange(parameters, addedLow, addedUpper);

        if (previousLow <= addedLow && previousUpper >= addedUpper) return parameters;

        require(
            addedLow < previousLow && addedUpper + 1 == previousLow
                || addedLow == previousUpper + 1 && addedUpper > previousUpper,
            "MSVault: invalid deposit range"
        );

        unchecked {
            uint24 newLow = addedLow == previousUpper + 1 ? previousLow : addedLow;
            uint24 newUpper = addedUpper + 1 == previousLow ? previousUpper : addedUpper;

            return _encodeRange(parameters, newLow, newUpper);
        }
    }

    /**
     * @dev Shrinks the range. The range will be shrunk to exclude the removed range.
     * The removed range must be inside the existing range and adjacent to the existing range.
     * If the removed range is the same as the existing range, the zero range will be returned.
     * @param parameters The current encoded parameters.
     * @param removedLow The low end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @return The new encoded range.
     */
    function _shrink(bytes32 parameters, uint24 removedLow, uint24 removedUpper) internal pure returns (bytes32) {
        (uint24 previousLow, uint24 previousUpper) = _decodeRange(parameters);

        if (removedLow == previousLow && removedUpper == previousUpper) return _encodeRange(parameters, 0, 0);

        require(
            (removedLow > previousLow && removedUpper == previousUpper)
                || (removedLow == previousLow && removedUpper < previousUpper),
            "MSVault: invalid withdraw range"
        );

        uint24 newLow = removedLow == previousLow ? uint24(_min(removedUpper + 1, previousUpper)) : previousLow;
        uint24 newUpper = removedUpper == previousUpper ? uint24(_max(removedLow - 1, previousLow)) : previousUpper;

        return _encodeRange(parameters, newLow, newUpper);
    }

    /**
     * @dev Returns the minimum of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The minimum of the two numbers.
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the maximum of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The maximum of the two numbers.
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the ids of the tokens in the range.
     * @param low The low end of the range.
     * @param upper The upper end of the range.
     * @return ids The ids of the tokens in the range.
     */
    function _getIds(uint24 low, uint24 upper) internal pure returns (uint256[] memory ids) {
        uint256 delta = upper - low + 1;

        ids = new uint256[](delta);

        for (uint256 i; i < delta;) {
            ids[i] = low + i;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Collects the fees from the pair.
     * @param parameters The encoded parameters.
     */
    function _collectFees(bytes32 parameters) internal {
        (uint24 low, uint24 upper) = _decodeRange(parameters);

        _pair().collectFees(address(this), _getIds(low, upper));
    }

    /**
     * @dev Withdraws the tokens from the pair.
     * @param pair The address of the pair.
     * @param removedLow The low end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     */
    function _withdraw(address pair, uint24 removedLow, uint24 removedUpper) internal {
        uint256 delta = removedUpper - removedLow + 1;

        uint256[] memory ids = new uint256[](delta);
        uint256[] memory amounts = new uint256[](delta);

        for (uint256 i; i < delta;) {
            ids[i] = removedLow + i;
            amounts[i] = ILBToken(pair).balanceOf(address(this), ids[i]);

            unchecked {
                ++i;
            }
        }

        ILBToken(pair).safeBatchTransferFrom(address(this), pair, ids, amounts);
        ILBPair(pair).burn(ids, amounts, address(this));
    }
}

