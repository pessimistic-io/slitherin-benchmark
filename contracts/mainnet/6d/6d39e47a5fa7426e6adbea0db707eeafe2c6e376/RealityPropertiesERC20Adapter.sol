// SPDX-License-Identifier: BUSL-1.1
// Reality NFT Contracts

pragma solidity 0.8.9;

import "./IRealityProperties.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Strings.sol";
import "./ERC165.sol";

/**
* @title Reality Properties ERC20 Adapter
* @notice This contract provides ERC20 capabilities for ERC1155 tokens of the Reality Properties contract.
* Each token within ERC1155 gets its own ERC20 address. The adapter operates on full fractional amounts
* with 18 decimal places. Each adapter is a minimal proxy and the main implementation is held by
* the Reality Properties contract.
* @dev The Context is not used by design
*/
contract RealityPropertiesERC20Adapter is ERC165, IERC20Metadata {
    IRealityProperties internal immutable entity;
    
    uint8 internal constant DECIMALS = 18;
    string internal constant SYMBOL = "RLTM";

    mapping(address => mapping(address => uint256)) private _allowances;

    constructor() {
        entity = IRealityProperties(msg.sender);
    }

    /**
     * Total supply
     */
    function totalSupply() external view returns (uint256){
        return entity.fractionalTotalSupply(address(this));
    }

    /**
     * Underlying ERC1155 token id
     */
    function id() external view returns (uint256){
        return entity.getTokenId(address(this));
    }

    /**
     * Name is 'RLTM:{tokenId}'
     */
    function name() external view returns (string memory){
        uint256 tokenId = entity.getTokenId(address(this));
        string memory fullSymbol = string(abi.encodePacked(SYMBOL, ":", Strings.toString(tokenId)));

        return fullSymbol;
    }

    /**
     * Symbol is 'RLTM:{tokenId}'
     */
    function symbol() external view returns (string memory){
        uint256 tokenId = entity.getTokenId(address(this));
        string memory fullSymbol = string(abi.encodePacked(SYMBOL, ":", Strings.toString(tokenId)));

        return fullSymbol;
    }

    /**
     * We use constant 18 decimal places
     */
    function decimals() external pure returns (uint8){
        return DECIMALS;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256){
        uint256 tokenId = entity.getTokenId(address(this));
        return entity.fractionalBalanceOf(account, tokenId);
    }

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool){
        emit Transfer(msg.sender, recipient, amount);

        entity.fractionalTransferByAdapter(msg.sender, recipient, amount);

        return true;
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `transferFrom`. This is
     * zero by default.
     *
     * This value changes when `approve` or `transferFrom` are called.
     */
    function allowance(address owner, address spender) public view returns (uint256){
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an `Approval` event.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     * Revert if not enough allowance is available.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        _decreaseAllowance(from, spender, amount);

        emit Transfer(from, to, amount);

        entity.fractionalTransferByAdapter(from, to, amount);

        return true;
    }
 
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return 
            interfaceId == type(IERC20Metadata).interfaceId || 
            interfaceId == type(IERC20).interfaceId || 
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
     function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = msg.sender;
        _decreaseAllowance(owner, spender, subtractedValue);
        return true;
    }

    function _decreaseAllowance(address owner, address spender, uint256 subtractedValue) internal {
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
    }

     /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
   function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

}
