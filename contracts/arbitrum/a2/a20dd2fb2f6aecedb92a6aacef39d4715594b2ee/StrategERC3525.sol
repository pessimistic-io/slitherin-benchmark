// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Strings.sol";
import "./ERC3525Upgradeable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./ERC2771ContextUpgradeable.sol";
import "./SafeERC20.sol";
import "./IStrategVaultFactory.sol";

error NotTokenOwner();
error ZeroBalanceToken();
error NotVault();
error ClaimDelayNotReached();

enum StrategERC3525UpdateType {
    Transfer,
    ReceiveRewards,
    Redeem
}

contract StrategERC3525 is ERC3525Upgradeable, ReentrancyGuard, ERC2771ContextUpgradeable {
    using Strings for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.

    struct TokenIdInfo {
        uint256 timeClaimed; // last time claimed
        uint256 lastClaimTotalRewards; // value of totalRewards during the last claim
    }

    IERC20 public tokenFee;
    uint256 constant RATIO = 1000;
    uint256 public totalRewards;
    uint256 public constant MAX_CLAIM_DELAY = 180 days; // max period to claim token

    address public vault;
    IStrategVaultFactory public factory;
    address public TREASURY; // à spécifier en dur l'adresse TREASURY
    mapping(uint256 => TokenIdInfo) public tokenIdInfo;

    event StrategERC3525Update(StrategERC3525UpdateType indexed update, bytes data);

    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function trustedForwarder() public view override returns (address) {
        return factory.relayer();
    }

    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @dev Initializes the contract with the specified owner and tokenFee.
     * @param _vault The address of the contract owner.
     * @param _owner The address of the contract owner.
     * @param _tokenFee The address of the ERC20 token to redeem for a proportional share.
     */
    function initialize(address _vault, address _owner, address _tokenFee, address _treasury, address _relayer) external initializer {
        __ERC3525_init("StrategERC3525", "SERC3525", 18);
        factory = IStrategVaultFactory(msg.sender);
        vault = _vault;
        tokenFee = IERC20(_tokenFee);
        TREASURY = _treasury;
        _mint(_owner, 1, RATIO);
    }

    /**
     * @dev Redeems tokens in the specified token ID.
     * @param _tokenId The ID of the token to redeem.
     */
    function redeem(uint256 _tokenId) public nonReentrant {
        if (balanceOf(_tokenId) == 0) revert ZeroBalanceToken();
        _claimRewards(_tokenId);
    }

    /**
     * @dev Adds rewards to the contract.
     * @param _amount The amount of tokens to add as rewards.
     */
    function addRewards(uint256 _amount) external {
        if (msg.sender != vault) revert NotVault();
        totalRewards += _amount;
        tokenFee.safeTransferFrom(vault, address(this), _amount);

        emit StrategERC3525Update(
            StrategERC3525UpdateType.ReceiveRewards, 
            abi.encode(address(tokenFee), _amount, block.timestamp)
        );
    }

    /**
     * @dev Function called before any token transfer occurs. Claims rewards for the sender and recipient if necessary.
     * @param _fromTokenId The ID of the token being transferred from.
     * @param _toTokenId The ID of the token being transferred to.
     */
    function _beforeValueTransfer(
        address _from,
        address _to,
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slot,
        uint256 _value
    )
        internal
        override
    {
        if (_fromTokenId != 0) _claimRewards(_fromTokenId);

        if (_exists(_toTokenId)) {
            _claimRewards(_toTokenId);
        } else {
            TokenIdInfo storage info = tokenIdInfo[_toTokenId];
            info.timeClaimed = block.timestamp;
            info.lastClaimTotalRewards = totalRewards;
        }

        emit StrategERC3525Update(
            StrategERC3525UpdateType.Transfer, 
            abi.encode(
                _from,
                _to,
                _fromTokenId,
                _toTokenId,
                _slot,
                _value
            )
        );
    }

    /**
     * @dev Redeems tokens in the treseaury address if token ID not claimed after 6 months.
     * @param _tokenId The ID of the token to redeem.
     */
    function pullUnclaimedToken(uint256 _tokenId) public {
        if (balanceOf(_tokenId) == 0) revert ZeroBalanceToken();
        TokenIdInfo storage info = tokenIdInfo[_tokenId];

        if (block.timestamp - info.timeClaimed <= MAX_CLAIM_DELAY) {
            revert ClaimDelayNotReached();
        }

        uint256 concernedRewards = totalRewards - info.lastClaimTotalRewards;
        uint256 feeClaimable = (concernedRewards * balanceOf(_tokenId)) / uint256(RATIO);

        if (feeClaimable > 0) {
            info.timeClaimed = block.timestamp;
            info.lastClaimTotalRewards = totalRewards;
            tokenFee.safeTransfer(TREASURY, feeClaimable);

            emit StrategERC3525Update(
                StrategERC3525UpdateType.Redeem, 
                abi.encode(_tokenId, TREASURY, feeClaimable)
            );
        }
    }

    /**
     * @dev Returns the URI for a specific token ID.
     * @param _tokenId The ID of the token to return the URI for.
     * @return The URI for the specified token ID.
     */
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        return string(abi.encodePacked("ERC3525"));
    }

    /**
     * @dev Calculates the rewards earned by the owner of a specific token ID and transfers them to the owner if there are any rewards to claim.
     * @param _tokenId The ID of the token to claim rewards for.
     * @return A boolean indicating whether the claim was successful.
     */
    function _claimRewards(uint256 _tokenId) internal returns (bool) {
        TokenIdInfo storage info = tokenIdInfo[_tokenId];
        address owner = ownerOf(_tokenId);
        uint256 concernedRewards = totalRewards - info.lastClaimTotalRewards;
        uint256 feeClaimable = (concernedRewards * balanceOf(_tokenId)) / uint256(RATIO);

        if (feeClaimable > 0) {
            info.timeClaimed = block.timestamp;
            info.lastClaimTotalRewards = totalRewards;
            tokenFee.safeTransfer(owner, feeClaimable);

            emit StrategERC3525Update(
                StrategERC3525UpdateType.Redeem, 
                abi.encode(_tokenId, owner, feeClaimable)
            );
        }

        return true;
    }
}

