pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

/**
 * @title Referral Hub Contract
 */

contract ReferralHub is OwnableUpgradeable {
    using SafeMath for uint256;

    address public did;
    address public dactToken;
    uint256 public amountPerReferral = 10 * 1e18;
    bool private isInitialized = false;

    mapping(uint256 => uint256) public referrals;

    mapping(uint256 => uint256) public totalReferrals;
    mapping(uint256 => mapping(uint256 => uint256)) public referredUsers;
    mapping(uint256 => uint256) public referredCounts;

    modifier onlyIdContract() {
        require(
            msg.sender == owner || did == msg.sender,
            "Referral Hub: NOT_WHITELISTED"
        );
        _;
    }

    modifier onlyInitializing() {
        require(!isInitialized, "initialized");
        _;
        isInitialized = true;
    }

    /// @notice Contract constructor
    constructor() public {}

    function initialize(
        address _id,
        address _dactToken,
        uint256 _amountPerReferral
    ) public onlyInitializing {
        __Ownable_init();
        did = _id;
        dactToken = _dactToken;
        amountPerReferral = _amountPerReferral;
    }

    function addReferral(
        uint256 _tokenId,
        uint256 _referredUserId
    ) external onlyIdContract returns (uint256) {
        referrals[_tokenId] = referrals[_tokenId].add(1);
        totalReferrals[_tokenId] = totalReferrals[_tokenId].add(1);
        referredUsers[_tokenId][referredCounts[_tokenId]] = _referredUserId;
        referredCounts[_tokenId] = referredCounts[_tokenId] + 1;
    }

    function claimReferral(
        uint256 _tokenId,
        address _to
    ) external onlyIdContract returns (uint256) {
        if (referrals[_tokenId] > 0) {
            IERC20(dactToken).transfer(
                _to,
                referrals[_tokenId] * amountPerReferral
            );
            referrals[_tokenId] = 0;
        }
    }

    function getReferral(uint256 _tokenId) external view returns (uint256) {
        return referrals[_tokenId] * amountPerReferral;
    }

    function getReferredUsers(
        uint256 _tokenId
    ) external view returns (uint256[] memory) {
        uint256[] memory users = new uint256[](referredCounts[_tokenId]);
        for (uint256 i = 0; i < referredCounts[_tokenId]; i++) {
            users[i] = referredUsers[_tokenId][i];
        }
        return users;
    }

    function setVariables(
        address _did,
        address _dactToken,
        uint256 _amountPerReferral
    ) external onlyOwner {
        did = _did;
        dactToken = _dactToken;
        amountPerReferral = _amountPerReferral;
    }

    uint256[49] private __gap;
}

