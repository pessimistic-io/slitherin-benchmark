//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IAssetToken.sol";
import "./IAssetReserver.sol";
import "./AssetToken.sol";
import "./AssetReserver.sol";

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract AssetTokenManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    event SetMinter(address sender, address minter, bool isMinter);
    event SetReserver(address sender, address reserver, bool isReserver);
    event SetAssetReserver(
        address sender,
        address asset,
        address reserver,
        bool isAssetReserver
    );
    event SetAsset(address sender, address asset, bool isAsset);
    event Mint(address indexed minter, address indexed token, uint256 amount);
    event Burn(address indexed minter, address indexed token, uint256 amount);
    event DeployAssetToken(address token, string name, string symbol);
    event DeployAssetReserver(address token, address reserver);
    event WithdrawFromReserver(address sender, address token, uint256 amount);

    mapping(address => bool) public minters;
    mapping(address => bool) public reservers;
    mapping(address => address) public assetsReservers; // asset => reserver
    mapping(address => bool) public assets;

    function addMinter(address minter) external onlyOwner {
        require(!minters[minter], "already minter");
        minters[minter] = true;
        emit SetMinter(msg.sender, minter, true);
    }

    function removeMinter(address minter) external onlyOwner {
        require(minters[minter], "!minter");
        minters[minter] = false;
        emit SetMinter(msg.sender, minter, false);
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "!minter");
        _;
    }

    function addReserver(address reserver) external onlyOwner {
        require(!reservers[reserver], "already reserver");
        reservers[reserver] = true;
        emit SetReserver(msg.sender, reserver, true);
    }

    function removeReserver(address reserver) external onlyOwner {
        require(reservers[reserver], "!reserver");
        reservers[reserver] = false;
        emit SetReserver(msg.sender, reserver, false);
    }

    function addAssetReserver(
        address asset,
        address reserver
    ) external onlyOwner {
        require(reservers[reserver], "!reserver");
        if (assetsReservers[asset] != address(0)) {
            revert("already assetReserver");
        }
        assetsReservers[asset] = reserver;
        emit SetAssetReserver(msg.sender, asset, reserver, true);
    }

    function removeAssetReserver(address asset) external onlyOwner {
        require(assetsReservers[asset] != address(0), "!reserver");
        assetsReservers[asset] = address(0);
        emit SetAssetReserver(msg.sender, asset, address(0), false);
    }

    function addAsset(address asset) external onlyOwner {
        require(!assets[asset], "already asset");
        assets[asset] = true;
        emit SetAsset(msg.sender, asset, true);
    }

    function removeAsset(address asset) external onlyOwner {
        require(assets[asset], "!asset");
        assets[asset] = false;
        emit SetAsset(msg.sender, asset, false);
    }

    modifier onlyAsset(address token) {
        require(assets[token], "!asset");
        _;
    }

    modifier onlyReserver(address reserver) {
        require(reservers[reserver], "!reserver");
        _;
    }

    function mint(
        address token,
        uint256 amount
    ) external onlyMinter onlyAsset(token) whenNotPaused {
        IAssetToken(token).mint(msg.sender, amount);
        emit Mint(msg.sender, token, amount);
    }

    function mintForReserver(
        address token,
        uint256 amount
    )
        external
        onlyMinter
        onlyAsset(token)
        onlyReserver(assetsReservers[token])
        whenNotPaused
    {
        IAssetToken(token).mint(assetsReservers[token], amount);
        emit Mint(assetsReservers[token], token, amount);
    }

    function checkAssetReserver(
        address asset,
        uint256 amount
    )
        external
        view
        onlyMinter
        onlyReserver(assetsReservers[asset])
        returns (bool)
    {
        require(amount > 0, "Amount must be greater than zero");
        uint256 assetBalance = IERC20(asset).balanceOf(assetsReservers[asset]);
        return assetBalance >= amount;
    }

    function withdrawFromReserver(
        address sender,
        address asset,
        uint256 amount
    ) external onlyMinter onlyReserver(assetsReservers[asset]) whenNotPaused {
        IAssetReserver(assetsReservers[asset]).withdrawFromReserver(
            sender,
            amount
        );
        emit WithdrawFromReserver(sender, address(this), amount);
    }

    function burn(
        address token,
        uint256 amount
    ) external onlyMinter onlyAsset(token) whenNotPaused {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IAssetToken(token).burn(amount);
        emit Burn(msg.sender, token, amount);
    }

    function burnForReserver(
        address token,
        uint256 amount
    )
        external
        onlyMinter
        onlyAsset(token)
        onlyReserver(assetsReservers[token])
        whenNotPaused
    {
        IAssetReserver(assetsReservers[token]).withdrawFromReserver(
            address(this),
            amount
        );
        IAssetToken(token).burn(amount);
        emit Burn(assetsReservers[token], token, amount);
    }

    function deployAssetToken(
        string memory name,
        string memory symbol
    ) external onlyOwner {
        AssetToken assetToken = new AssetToken(name, symbol);
        emit DeployAssetToken(address(assetToken), name, symbol);
    }

    function deployAssetReserver(
        address asset
    ) external onlyOwner {
        AssetReserver assetReserver = new AssetReserver(
            IERC20(asset),
            address(this)
        );
        emit DeployAssetReserver(asset, address(assetReserver));
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }
}

