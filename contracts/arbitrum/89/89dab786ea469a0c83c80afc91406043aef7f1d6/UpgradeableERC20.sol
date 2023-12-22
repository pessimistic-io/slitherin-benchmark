// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./console.sol";
import {Context} from "./Context.sol";
import {IERC20} from "./IERC20.sol";
import {SafeMath} from "./SafeMath.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {Errors} from "./Errors.sol";
import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {IGuild} from "./IGuild.sol";
import {IACLManager} from "./IACLManager.sol";
import {ERC20Storage} from "./ERC20Storage.sol";

/**
 * @title UpgradeableERC20
 * @author Tazz Labs, inspired by the Openzeppelin ERC20, and AAVE IncentivizedERC20 implementation
 * @notice Basic ERC20 implementation
 **/
abstract contract UpgradeableERC20 is ERC20Storage, Context, IERC20Detailed {
    using WadRayMath for uint256;
    using SafeMath for uint256;

    //Upgradeability and ownership variables (not stored in proxy given immutable)
    IGuildAddressesProvider internal immutable _addressesProvider;
    IGuild public immutable GUILD;

    /**
     * @dev Only guild admin can call functions marked by this modifier.
     **/
    modifier onlyGuildAdmin() {
        IACLManager aclManager = IACLManager(_addressesProvider.getACLManager());
        require(aclManager.isGuildAdmin(msg.sender), Errors.CALLER_NOT_GUILD_ADMIN);
        _;
    }

    /**
     * @dev Only guild can call functions marked by this modifier.
     **/
    modifier onlyGuild() {
        require(_msgSender() == address(GUILD), Errors.CALLER_MUST_BE_GUILD);
        _;
    }

    /**
     * @dev Constructor.
     * @param guild The reference to the main Guild contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals The number of decimals of the token
     */
    constructor(
        IGuild guild,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) {
        _addressesProvider = guild.ADDRESSES_PROVIDER();
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        GUILD = guild;
    }

    /// @inheritdoc IERC20Detailed
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Detailed
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20Detailed
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual override returns (bool) {
        require(_allowances[sender][_msgSender()] >= amount, Errors.TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    /**
     * @notice Increases the allowance of spender to spend _msgSender() tokens
     * @param spender The user allowed to spend on behalf of _msgSender()
     * @param addedValue The amount being added to the allowance
     * @return `true`
     **/
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @notice Decreases the allowance of spender to spend _msgSender() tokens
     * @param spender The user allowed to spend on behalf of _msgSender()
     * @param subtractedValue The amount being subtracted to the allowance
     * @return `true`
     **/
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        require(_allowances[_msgSender()][spender] >= subtractedValue, Errors.NEGATIVE_ALLOWANCE_NOT_ALLOWED);
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
        return true;
    }

    /**
     * @notice Transfers tokens between two users.
     * @param sender The source address
     * @param recipient The destination address
     * @param amount The amount getting transferred
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(_balances[sender] >= amount, Errors.TRANSFER_EXCEEDS_BALANCE);
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }

    /**
     * @notice Approve `spender` to use `amount` of `owner`s balance
     * @param owner The address owning the tokens
     * @param spender The address approved for spending
     * @param amount The amount of tokens to approve spending of
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

