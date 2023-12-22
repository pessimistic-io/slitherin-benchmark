// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.9;

// Importing required OpenZeppelin contracts and interfaces
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./ERC4626.sol";
import "./SafeERC20.sol";

// Interface for tokens that can be burned
interface IBurnable {
    function burn(address _account, uint256 _amount) external;
}

// Interface for tokens that can be minted
interface IMintable {
    function mint(address _account, uint256 _amount) external;
}

// Interface for the migration token, which combines IERC20, IBurnable, and IMintable interfaces
interface IMigrationToken is IERC20, IBurnable, IMintable {

}

// The main contract for USDR migration
contract USDRMigrationV2 is Ownable, Pausable {
    // Using SafeERC20 for safe token transfers
    using SafeERC20 for IERC20;

    // Address of the Multichain vault, which is constant
    address public constant MULTICHAIN_VAULT =
        0x52b9D0F46451bd2c610Ae6Ab1F5312a35A6159E3;

    // Addresses of the old and new USDR and WUSDR tokens, which are set once and not changed
    address public immutable oldUSDR;
    address public immutable oldWUSDR;
    address public immutable usdr;
    address public immutable wusdr;

    // Snapshot of the initial WUSDR balance or total supply, which is used to ensure integrity
    uint256 private immutable _snapshot;

    // Hashes of the rescue operations to prevent repetition
    mapping(bytes32 => bool) _rescueHashes;

    // Events for logging migration and rescue operations
    event Migrate(
        address indexed fromToken,
        address indexed toToken,
        address indexed account,
        uint256 amount
    );
    event Rescue(bytes32 indexed hash, address indexed account, uint256 amount);

    // Flag to indicate whether it's the main chain
    bool private _isMain;

    // Constructor for initializing the contract
    constructor(
        address _oldUSDR,
        address _oldWUSDR,
        address _usdr,
        address _wusdr,
        bool _isMainChain
    ) {
        oldUSDR = _oldUSDR;
        oldWUSDR = _oldWUSDR;
        usdr = _usdr;
        wusdr = _wusdr;
        _isMain = _isMainChain;
        // Save a snapshot of the initial WUSDR balance or total supply
        _snapshot = _isMainChain
            ? IERC20(_oldWUSDR).balanceOf(MULTICHAIN_VAULT)
            : IERC20(_oldWUSDR).totalSupply();
    }

    // Function to pause the contract, can only be called by the contract owner and when not paused
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    // Function to unpause the contract, can only be called by the contract owner and when paused
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    // Function to perform the migration, can only be called when not paused
    function migrate() external whenNotPaused {
        _checkSnapshot();
        if (_isMain) {
            _migrateUSDR();
        }
        _migrateWUSDR();
    }

    // Function to rescue wrapped USDR on chains other than the main chain
    function rescueWrappedUSDR(
        address _account,
        uint256 _amount,
        bytes32 _hash
    ) external onlyOwner {
        // Rescue operations can only be performed on chains other than the main chain
        require(!_isMain, "no rescue on main chain");
        // Each rescue operation must be unique
        require(!_rescueHashes[_hash], "already rescued");
        IMintable(oldWUSDR).mint(_account, _amount);
        emit Rescue(_hash, _account, _amount);
    }

    // Function to check the integrity of the WUSDR token
    function _checkSnapshot() internal view {
        if (_isMain) {
            // On the main chain, ensure that the balance of the Multichain WUSDR vault has not changed
            require(
                _snapshot == IERC20(oldWUSDR).balanceOf(MULTICHAIN_VAULT),
                "suspicious activity"
            );
        } else {
            // On other chains, ensure that the total supply of the Multichain WUSDR tokens has not changed
            require(
                _snapshot == IERC20(oldWUSDR).totalSupply(),
                "suspicious activity"
            );
        }
    }

    // Function to migrate USDR tokens from the old contract to the new one
    function _migrateUSDR() internal {
        address _sender = _msgSender();
        IMigrationToken _oldUSDR = IMigrationToken(oldUSDR);
        uint256 _balance = _oldUSDR.balanceOf(_sender);
        if (_balance != 0) {
            _migrateUSDR(_sender, _balance);
        }
    }

    // Function to burn old USDR tokens and mint new ones
    function _migrateUSDR(address _sender, uint256 _amount) internal {
        IMigrationToken _oldUSDR = IMigrationToken(oldUSDR);
        IMintable _usdr = IMintable(usdr);
        _oldUSDR.burn(_sender, _amount);
        _usdr.mint(_sender, _amount);
        emit Migrate(oldUSDR, usdr, _sender, _amount);
    }

    // Function to migrate WUSDR tokens from the old contract to the new one
    function _migrateWUSDR() internal {
        address _sender = _msgSender();
        if (_isMain) {
            ERC4626 _oldWUSDR = ERC4626(oldWUSDR);
            ERC4626 _wusdr = ERC4626(wusdr);
            uint256 _balance = _oldWUSDR.balanceOf(_sender);
            if (_balance != 0) {
                // Redeem the underlying assets from the old WUSDR tokens
                uint256 _assets = _oldWUSDR.redeem(
                    _balance,
                    address(this),
                    _sender
                );
                // Migrate the underlying USDR tokens to the new contract
                _migrateUSDR(address(this), _assets);
                // Approve the new WUSDR contract to spend the newly minted USDR tokens
                IERC20(usdr).approve(wusdr, _assets);
                // Deposit the USDR tokens into the new WUSDR contract and get shares
                uint256 _shares = _wusdr.deposit(_assets, _sender);
                emit Migrate(oldWUSDR, wusdr, _sender, _shares);
            }
        } else {
            IERC20 _oldWUSDR = IERC20(oldWUSDR);
            IMintable _wusdr = IMintable(wusdr);
            uint256 _balance = _oldWUSDR.balanceOf(_sender);
            if (_balance != 0) {
                // Transfer the old WUSDR tokens to the contract
                _oldWUSDR.safeTransferFrom(_sender, address(this), _balance);
                // Mint new WUSDR tokens for the sender
                _wusdr.mint(_sender, _balance);
                emit Migrate(oldWUSDR, wusdr, _sender, _balance);
            }
        }
    }
}

