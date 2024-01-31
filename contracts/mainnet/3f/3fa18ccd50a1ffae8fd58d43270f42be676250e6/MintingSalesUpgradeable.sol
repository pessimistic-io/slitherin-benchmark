// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

abstract contract MintingSalesUpgradeable is Initializable, ContextUpgradeable {
    using SafeMathUpgradeable for uint256;

    struct SalesInfo {
        uint256 mintStartIndex;      // First index for minting
        uint256 maxMintingAmount;    // Maximum volume of minting
        uint64 mintStartTimestamp;   // Start timestamp of minting
        uint64 mintEndTimestamp;     // End timestamp of minting
        uint8 mintLimitPerOnce;      // Limit per once for minting
        uint8 whitelistLimitPerOnce; // Whitelist limit per once for minting
    }

    SalesInfo private _salesInfo;
    uint256 private _mintingCount;
    uint256 private _salesIndex;

    /**
     * @dev Emitted when withdraw payment.
     * @param to The address to receive payment.
     * @param amount A mount of send to collector.
     */
    event Withdraw(address to, uint256 amount);

    /**
     * @dev Emitted when set up a minting sales.
     * @param salesInfo The minting sales info.
     */
    event SetupSales(SalesInfo salesInfo);

    modifier salesValidator(uint8 requestedCount, bool isWhitelist) {
        require(isMintingActive(), "Sales: Minting is not active");
        require(_mintingCount < _salesInfo.maxMintingAmount, "Sales: sold out");
        require(requestedCount > 0 &&
            requestedCount <= (isWhitelist ? _salesInfo.whitelistLimitPerOnce : _salesInfo.mintLimitPerOnce)
            , "Sales: too many request or zero request");
        _;
    }

    function __MintingSales_init() internal onlyInitializing {
        __MintingSales_init_unchained();
    }

    function __MintingSales_init_unchained() internal onlyInitializing {}

    /**
     * @dev Returns whether minting is active
     */
    function isMintingActive() public view returns (bool) {
        if (_salesInfo.mintStartTimestamp == 0) return false;
        return 
            _salesInfo.mintEndTimestamp > 0
            ? block.timestamp >= _salesInfo.mintStartTimestamp && block.timestamp <= _salesInfo.mintEndTimestamp
            : block.timestamp >= _salesInfo.mintStartTimestamp;
    }

    /**
     * @dev Returns sales infomation
     */
    function salesInfo() public view returns (SalesInfo memory) {
        return _salesInfo;
    }

    /**
     * @dev Returns sales Index;
     */
    function salesIndex() public view returns (uint256) {
        return _salesIndex;
    }

    /**
     * @dev Returns current minting Count;
     */
    function currentMintCount() public view returns (uint256) {
        return _mintingCount;
    }

    /**
     * @dev Count minting and add sales index.
     */
    function _mintCounting() internal virtual {
        _salesIndex++;
        _mintingCount++;
    }

    /**
     * @dev Set Minting options.
     * @param mintStartIndex First index for minting.
     * @param maxMintingAmount Maximum volume of minting.
     * @param mintStartTimestamp Start timestamp of minting.
     * @param mintEndTimestamp End timestamp of minting.
     * @param mintLimitPerOnce Limit per once for minting.
     * @param whitelistLimitPerOnce Whitelist limit per once for minting.
     */
    function _setupMinting(
        uint256 mintStartIndex,
        uint256 maxMintingAmount,
        uint64 mintStartTimestamp,
        uint64 mintEndTimestamp,        
        uint8 mintLimitPerOnce,
        uint8 whitelistLimitPerOnce
    ) 
        internal virtual
    {
        _salesInfo = SalesInfo(
            mintStartIndex,
            maxMintingAmount,
            mintStartTimestamp,
            mintEndTimestamp,
            mintLimitPerOnce,
            whitelistLimitPerOnce
        );
        _mintingCount = 0;
        _salesIndex = mintStartIndex;
        emit SetupSales(_salesInfo);
    }
}
