// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract IRDToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("iRD", "iRD");
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    struct ConvertData {
        uint256 lockAmount;
        uint256 claimedAmount;
        uint startClaimTimestamp;
    }
    mapping(address => ConvertData) public convertData;
    mapping(address => bool) private _whitelistTransferAddresses;
    mapping(address => bool) private _blacklistConvertAddresses;
    address public convertToken;
    uint public totalClaimDuration;
    bool public isConvertEnabled;
    bool public isClaimEnabled;

    event ConvertRDSucceed(address sender, uint256 amount, uint256 timestamp);

    event ClaimRDSucceed(address sender, uint256 amount, uint256 timestamp);

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier convertEnabled() {
        require(isConvertEnabled, "Convert is disabled");
        _;
    }

    modifier claimEnabled() {
        require(isClaimEnabled, "Claim is disabled");
        _;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(_whitelistTransferAddresses[msg.sender], "The address is not on the whitelist");
        _transfer(_msgSender(), to, amount);
        return true;
    }

    /**
     * @notice Add to whitelist
     */
    function addToTransferWhitelist(
        address[] calldata toAddAddresses
    ) external onlyOwner {
        for (uint i = 0; i < toAddAddresses.length; i++) {
            _whitelistTransferAddresses[toAddAddresses[i]] = true;
        }
    }

    /**
     * @notice Remove from whitelist
     */
    function removeFromTransferWhitelist(
        address[] calldata toRemoveAddresses
    ) external onlyOwner {
        for (uint i = 0; i < toRemoveAddresses.length; i++) {
            delete _whitelistTransferAddresses[toRemoveAddresses[i]];
        }
    }

    /**
     * @notice Add to blacklist
     */
    function addToConvertBlacklist(
        address[] calldata toAddAddresses
    ) external onlyOwner {
        for (uint i = 0; i < toAddAddresses.length; i++) {
            _blacklistConvertAddresses[toAddAddresses[i]] = true;
        }
    }

    /**
     * @notice Remove from blacklist
     */
    function removeFromConvertBlacklist(
        address[] calldata toRemoveAddresses
    ) external onlyOwner {
        for (uint i = 0; i < toRemoveAddresses.length; i++) {
            delete _blacklistConvertAddresses[toRemoveAddresses[i]];
        }
    }

    /**
     * @dev Set Token for vesting
     * @param tokenAddress token for vesting
     */
    function setConvertToken(address tokenAddress) public onlyOwner {
        convertToken = tokenAddress;
    }

    /**
     * @dev Set total unlock duration
     * @param duration Total Lock duration by timestamp
     */
    function setTotalClaimDuration(uint duration) public onlyOwner {
        totalClaimDuration = duration;
    }

    /**
     * @dev Set start convert token
     */
    function startConvert() public onlyOwner {
        require(!isConvertEnabled, "Cannot start convert time");
        isConvertEnabled = true;
    }

    /**
     * @dev Set stop convert token
     */
    function stopConvert() public onlyOwner {
        require(isConvertEnabled, "Cannot stop convert time");
        isConvertEnabled = false;
    }

    /**
     * @dev Set start claim token
     */
    function startClaim() public onlyOwner {
        require(!isClaimEnabled, "Cannot start claim time");
        isClaimEnabled = true;
    }

    /**
     * @dev Set stop claim token
     */
    function stopClaim() public onlyOwner {
        require(isClaimEnabled, "Cannot stop claim time");
        isClaimEnabled = false;
    }

    /**
     * @dev Withdraw fund to recipient
     * @param recipient receive address
     * * @param token token contract address
     */
    function withdrawFund(address recipient, address token) public onlyOwner {
        IERC20Upgradeable(token).transfer(
            recipient,
            IERC20Upgradeable(token).balanceOf(address(this))
        );
    }

    /**
     * @dev Get Claimable sell oken
     * @param claimAddress Adddress of buyer
     * @return Amount sell token can claimed
     **/
    function getClaimable(address claimAddress) public view returns (uint256) {
        if (!isClaimEnabled) {
            return 0;
        }

        uint256 totalLockAmount = convertData[claimAddress].lockAmount;
        if (totalLockAmount == 0) {
            return 0;
        }

        if (convertData[claimAddress].startClaimTimestamp == 0) {
            return 0;
        }

        uint256 tokenPerTimestamp = totalLockAmount / totalClaimDuration;
        uint progressTimestamp = block.timestamp - convertData[claimAddress].startClaimTimestamp;

        uint256 fullClaimableAmount;
        if (progressTimestamp > totalClaimDuration) {
            fullClaimableAmount = totalLockAmount;
        } else {
            fullClaimableAmount = progressTimestamp * tokenPerTimestamp;
        }
        
        return fullClaimableAmount - convertData[claimAddress].claimedAmount;
    }

    function convertRD(uint256 amount) public convertEnabled nonReentrant {
        require(!_blacklistConvertAddresses[msg.sender], "The address is on the blacklist");
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(msg.sender) >= amount, "Balance is not enough");
        
        if (convertData[msg.sender].startClaimTimestamp == 0) {
            convertData[msg.sender].lockAmount = amount;
            convertData[msg.sender].claimedAmount = 0;
            convertData[msg.sender].startClaimTimestamp = block.timestamp;
        } else {
            require(convertData[msg.sender].startClaimTimestamp + totalClaimDuration >= block.timestamp, "Cannot convert, please claim first");
            convertData[msg.sender].startClaimTimestamp = (amount * block.timestamp + convertData[msg.sender].lockAmount * convertData[msg.sender].startClaimTimestamp) / (amount + convertData[msg.sender].lockAmount);
            convertData[msg.sender].lockAmount += amount;
        }

        _burn(msg.sender, amount);

        emit ConvertRDSucceed(msg.sender, amount, block.timestamp);
    }

    function claimRD() public claimEnabled nonReentrant {
        require(convertData[msg.sender].startClaimTimestamp > 0, "Cannot claim, please convert first");
        uint256 claimableAmount = getClaimable(msg.sender);
        require(claimableAmount > 0, "Claimable amount must be greater than zero");

        convertData[msg.sender].claimedAmount += claimableAmount;

        if (convertData[msg.sender].claimedAmount == convertData[msg.sender].lockAmount) {
            convertData[msg.sender].startClaimTimestamp = 0;
        }

        IERC20Upgradeable(convertToken).transfer(msg.sender, claimableAmount);

        emit ClaimRDSucceed(msg.sender, claimableAmount, block.timestamp);
    }
}

