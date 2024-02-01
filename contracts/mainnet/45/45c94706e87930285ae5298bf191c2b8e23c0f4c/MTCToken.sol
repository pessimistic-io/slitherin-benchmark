// SPDX-License-Identifier: No License

pragma solidity 0.8.18;

/**
 * @title Próspera Tax Credit Token
 * @notice Marketable Tax Credit implementation for Próspera ZEDE
 *
 * Próspera Tax Credit tokens (“PTC”s) are minted by the Roatán Financial Services Authority (“RFSA”)
 * on behalf of Próspera ZEDE as “MTC Tokens” pursuant to Section 3 of the Próspera Resolution
 * Authorizing MTC Tokens, §5-1-199-0-0-0-1. As such, PTCs are both utility tokens and Qualifying
 * Cryptocurrency in Próspera ZEDE. 
 * 
 * Please see the terms and conditions of use at https://www.rfsa.hn/tos
 *
 * Note: this contract is meant to be deployed behind an upgradeable proxy. This means any subsequent
 * implementation contracts must retain the storage layout of this contract or risk storage collision.
 *
 */

import { ERC20Upgradeable, IERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { Ownable2StepUpgradeable } from "./Ownable2StepUpgradeable.sol";
import { IMTCToken } from "./IMTCToken.sol";
import { Blacklist } from "./Blacklist.sol";

contract MTCToken is IMTCToken, Blacklist, ERC20Upgradeable, Ownable2StepUpgradeable {

    /****************************************************************
     *                      State Variables                         
     ****************************************************************/

    /// The account for the issuing tax entity
    /// Note: If taxpayers pay taxes using `MTC Tokens` the received funds go to this address
    /// NB: The `burner` account can ONLY burn tokens at this address
    address internal liquidityAccount;

    /// The accounts that can `mint` new MTC Tokens
    mapping(address => bool) internal minters;

    /// The accounts that can `burn` MTC tokens held by `liquidityAccount`
    mapping(address => bool) internal burners;

    /****************************************************************
     *                        Modifiers                             
     ****************************************************************/

    /**
     * @dev Access control: Minter
     */
    modifier onlyMinter() {
        /// If NOT(`minters[msg.sender] == true)`, revert
        if (!checkMinter(msg.sender)) revert NotMinter();
        _;
    }

    /**
     * @dev Access control: Burner
     */
    modifier onlyBurner() {
        /// If NOT(`burners[msg.sender] == true)`, revert
        if (!checkBurner(msg.sender)) revert NotBurner();
        _;
    }

    /****************************************************************
     *                      Constructor                             
     ****************************************************************/

    /**
     * @dev `_disableInitializers` prevents intitialization of the implementation contract
     */
    constructor() {
       _disableInitializers();
    }

    /****************************************************************
     *                   Initialization Logic                     
     ****************************************************************/

    /// @inheritdoc IMTCToken
    function initialize(
        address initialMinter,
        address initialBurner,
        address initialBlacklister,
        address initialLiquidityAccount
    ) external initializer {
        /// Check that initial accounts are not zero address
        if (
            initialLiquidityAccount == address(0x00) ||
            initialBlacklister == address(0x00) ||
            initialMinter == address(0x00) ||
            initialBurner == address(0x00)
        ) {
            revert InvalidTarget();
        }

        /// Initialize the inherited upgradeable contracts
        __ERC20_init("Prospera Tax Credit", "PTC");
        __Ownable2Step_init();

        /// Set up the `burner`, `minter`, `liquidityAccount` and `burner`
        minters[initialMinter] = true;
        burners[initialBurner] = true;
        liquidityAccount = initialLiquidityAccount;

        _initializeBlacklist(initialBlacklister);
    }

    /****************************************************************
     *                     Business Logic                           
     ****************************************************************/

    /// @inheritdoc IMTCToken
    function mint(address to, uint256 amount) external onlyMinter {
        if (isBlacklisted(to)) revert AccountBlacklisted();
        _mint(to, amount);
    }

    /// @inheritdoc IMTCToken
    function blacklistAccounts(address[] calldata targets) external onlyBlacklister {
        if (targets.length == 0) revert EmptyArray();

        /// Note: To prevent unnecessary reverts if an already blacklisted account is
        /// included in `targets` it will still execute `_blacklistAccount`.
        /// It is NB that the trusted `blacklister` sanitizes inputs to avoid wasting gas.
        uint256 accounts = targets.length;
        for (uint256 i; i < accounts; ++i) {
           if (_checkTargetValidity(targets[i])) {
                _blacklistAccount(targets[i]);
            }
        }
    }

    /// @inheritdoc IMTCToken
    function revokeBlacklistings(address[] calldata targets) external onlyBlacklister {
        uint256 accounts = targets.length;
        for (uint256 i; i < accounts; ++i) {
            _revokeBlacklisting(targets[i]);
        }
    }

    /// @inheritdoc IMTCToken
    function burn(uint256 amount) external onlyBurner {
        _burn(liquidityAccount, amount);
        emit Burnt(amount);
    }

    /****************************************************************
     *                    Setter Functions                          
     ****************************************************************/

    /// @inheritdoc IMTCToken
    function setMinter(address newMinter) public onlyOwner {
        if (!_checkTargetValidity(newMinter)) revert InvalidTarget();
        minters[newMinter] = true;

        emit NewMinter(newMinter);
    }

    /// @inheritdoc IMTCToken
    function removeMinter(address minter) external onlyOwner {
        if (!minters[minter]) revert InvalidTarget();

        delete minters[minter];

        emit MinterRemoved(minter);
    }

    /// @inheritdoc IMTCToken
    function setBurner(address newBurner) public onlyOwner {
        if (!_checkTargetValidity(newBurner)) revert InvalidTarget();
        burners[newBurner] = true;

        emit NewBurner(newBurner);
    }

    /// @inheritdoc IMTCToken
    function removeBurner(address burner) external onlyOwner {
        if (!burners[burner]) revert InvalidTarget();

        delete burners[burner];

        emit BurnerRemoved(burner);
    }

    /// @inheritdoc IMTCToken
    function setBlacklister(address newBlacklister) external onlyOwner {
        if (!_checkTargetValidity(newBlacklister)) revert InvalidTarget();

        _setBlacklister(newBlacklister);
    }

    /// @inheritdoc IMTCToken
    function setNewLiquidityAccount(address newWallet) external onlyOwner {
        if (!_checkTargetValidity(newWallet)) revert InvalidTarget();
        /// The `burner` account loses the ability to `burn` tokens in the old `liquidityAccount` wallet
        /// If the account is not empty `transfer` all `MTC`s to the new wallet
        /// Note this requires an `approve` call prior to `setNewLiquidityAccount`
        if (balanceOf(liquidityAccount) != 0) {
            transferFrom(liquidityAccount, newWallet, balanceOf(liquidityAccount));
        }

        liquidityAccount = newWallet;

        emit NewLiquidityAccount(newWallet);
    }

    /****************************************************************
     *                    Getter Functions                          
     ****************************************************************/

    /**
     * @dev Check if a `target` is the burner account
     */
    function checkBurner(address target) public view returns (bool) {
        return burners[target];
    }

    /**
     * @dev Check if a `target` is the minter account
     */
    function checkMinter(address target) public view returns (bool) {
        return minters[target];
    }

    /**
     * @dev Returns the `liquidityAccount`
     */
    function getLiquidityAccount() public view returns (address) {
        return liquidityAccount;
    }

    /**
     * @dev Returns the decimals
     * Note: only for display purposes
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /****************************************************************
     *                    Internal Utility Logic                    
     ****************************************************************/
    /// @inheritdoc ERC20Upgradeable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override view {
        if (isBlacklisted(from) || isBlacklisted(to)) revert AccountBlacklisted();
    }

    /**
     * @dev Check that `target` is an address not currently in use and is not zero address
     */
    function _checkTargetValidity(address target) internal view returns (bool) {
        if (
            minters[target] ||
            burners[target] ||
            target == address(0x00) ||
            target == blacklister ||
            target == liquidityAccount
        ) {
            return false;
        }

        return true;
    }
}
