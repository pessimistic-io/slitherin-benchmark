// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./console.sol";

contract DgenesisReservation is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public dgvToken;

    uint256 public nextProjectId;
    mapping(uint256 => Project) projects;

    struct Project {
        string name;
        uint256 pricePerTokenInWei;
        uint256 dgvPerTokenInWei;
        uint256 dgvRewardPerTokenInWei;
        uint256 totalReserved;
        uint256 maxTotalReserveable;
        uint256 activeTime;
        uint256 inactiveTime;
        uint256 maxReservationsPerAddress;
        mapping(address => uint256) Reservations;
        bool paused;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(address _dgvToken) {
        dgvToken = IERC20(_dgvToken);
    }

    /* ========== VIEWS ========== */
    function getProjectName(uint256 _projectId)
        public
        view
        returns (string memory)
    {
        return projects[_projectId].name;
    }

    function getProjectActiveTime(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].activeTime;
    }

    function getProjectMaxReservationsPerAddress(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].maxReservationsPerAddress;
    }

    function getProjectInactiveTime(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].inactiveTime;
    }

    function getProjectPaused(uint256 _projectId) public view returns (bool) {
        return projects[_projectId].paused;
    }

    function getProjectTotalReserved(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].totalReserved;
    }

    function getProjectMaxTotalReserveable(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].maxTotalReserveable;
    }

    function getProjectPricePerTokenInWei(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].pricePerTokenInWei;
    }

    function getProjectDgvPerTokenInWei(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].dgvPerTokenInWei;
    }

    function getProjectDgvRewardPerTokenInWei(uint256 _projectId)
        public
        view
        returns (uint256)
    {
        return projects[_projectId].dgvRewardPerTokenInWei;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function reserve(uint256 _projectId, uint256 _amount)
        external
        payable
        nonReentrant
    {
        require(_amount > 0, "Cannot reserve 0");
        require(
            _amount.add(projects[_projectId].totalReserved) <=
                projects[_projectId].maxTotalReserveable,
            "Over limit"
        );
        require(
            block.timestamp >= projects[_projectId].activeTime,
            "Have not reached active time"
        );
        require(
            block.timestamp <= projects[_projectId].inactiveTime,
            "Have passed active time period"
        );
        require(
            projects[_projectId].pricePerTokenInWei.mul(_amount) <= msg.value,
            "Ether value sent is not correct"
        );
        require(
            projects[_projectId].Reservations[msg.sender].add(_amount) <=
                projects[_projectId].maxReservationsPerAddress,
            "Max Reservations Per Account Exceeded"
        );

        projects[_projectId].totalReserved = projects[_projectId]
            .totalReserved
            .add(_amount);

        if (
            projects[_projectId].dgvPerTokenInWei >
            projects[_projectId].dgvRewardPerTokenInWei
        ) {
            uint256 difference = _amount
                .mul(projects[_projectId].dgvPerTokenInWei)
                .sub(_amount.mul(projects[_projectId].dgvRewardPerTokenInWei));
            dgvToken.safeTransferFrom(msg.sender, address(this), difference);
        } else if (
            projects[_projectId].dgvPerTokenInWei <
            projects[_projectId].dgvRewardPerTokenInWei
        ) {
            uint256 difference = _amount
                .mul(projects[_projectId].dgvRewardPerTokenInWei)
                .sub(_amount.mul(projects[_projectId].dgvPerTokenInWei));
            dgvToken.safeTransfer(msg.sender, difference);
        }

        projects[_projectId].Reservations[msg.sender] = projects[_projectId]
            .Reservations[msg.sender]
            .add(_amount);

        emit Reserved(msg.sender, _projectId, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function createProject(
        string memory _name,
        uint256 _pricePerTokenInWei,
        uint256 _dgvPerTokenInWei,
        uint256 _dgvRewardPerTokenInWei,
        uint256 _maxTotalReserveable,
        uint256 _activeTime,
        uint256 _inactiveTime,
        uint256 _maxReservationsPerAddress
    ) public onlyOwner {
        uint256 projectId = nextProjectId;

        projects[projectId].name = _name;
        projects[projectId].pricePerTokenInWei = _pricePerTokenInWei;
        projects[projectId].dgvRewardPerTokenInWei = _dgvRewardPerTokenInWei;
        projects[projectId].dgvPerTokenInWei = _dgvPerTokenInWei;
        projects[projectId].maxTotalReserveable = _maxTotalReserveable;
        projects[projectId].activeTime = _activeTime;
        projects[projectId].inactiveTime = _inactiveTime;
        projects[projectId]
            .maxReservationsPerAddress = _maxReservationsPerAddress;
        projects[projectId].paused = false;
        nextProjectId = nextProjectId + 1;
    }

    function modifyProject(
        uint256 _projectId,
        string memory _name,
        uint256 _pricePerTokenInWei,
        uint256 _dgvPerTokenInWei,
        uint256 _dgvRewardPerTokenInWei,
        uint256 _maxTotalReserveable,
        uint256 _activeTime,
        uint256 _inactiveTime,
        uint256 _maxReservationsPerAddress
    ) public onlyOwner {
        projects[_projectId].name = _name;
        projects[_projectId].pricePerTokenInWei = _pricePerTokenInWei;
        projects[_projectId].dgvRewardPerTokenInWei = _dgvRewardPerTokenInWei;
        projects[_projectId].dgvPerTokenInWei = _dgvPerTokenInWei;
        projects[_projectId].maxTotalReserveable = _maxTotalReserveable;
        projects[_projectId].activeTime = _activeTime;
        projects[_projectId].inactiveTime = _inactiveTime;
        projects[_projectId]
            .maxReservationsPerAddress = _maxReservationsPerAddress;
    }

    function setProjectPrice(uint256 _projectId, uint256 _pricePerTokenInWei)
        public
        onlyOwner
    {
        projects[_projectId].pricePerTokenInWei = _pricePerTokenInWei;
    }

    function setProjectReward(
        uint256 _projectId,
        uint256 _dgvRewardPerTokenInWei
    ) public onlyOwner {
        projects[_projectId].dgvRewardPerTokenInWei = _dgvRewardPerTokenInWei;
    }

    function setProjectDGVPrice(uint256 _projectId, uint256 _dgvPerTokenInWei)
        public
        onlyOwner
    {
        projects[_projectId].dgvPerTokenInWei = _dgvPerTokenInWei;
    }

    function setProjectMaxReservationsPerAddress(
        uint256 _projectId,
        uint256 _maxReservationsPerAddress
    ) public onlyOwner {
        projects[_projectId]
            .maxReservationsPerAddress = _maxReservationsPerAddress;
    }

    function setProjectMaxTotalReservable(
        uint256 _projectId,
        uint256 _maxTotalReserveable
    ) public onlyOwner {
        projects[_projectId].maxTotalReserveable = _maxTotalReserveable;
    }

    function setProjectActiveTime(uint256 _projectId, uint256 _activeTime)
        public
        onlyOwner
    {
        projects[_projectId].activeTime = _activeTime;
    }

    function setProjectInactiveTime(uint256 _projectId, uint256 _inactiveTime)
        public
        onlyOwner
    {
        projects[_projectId].inactiveTime = _inactiveTime;
    }

    function setProjectPaused(uint256 _projectId, bool _isPaused)
        public
        onlyOwner
    {
        projects[_projectId].paused = _isPaused;
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
    }

    function withdraw(address payable recipient, uint256 amount)
        public
        onlyOwner
    {
        recipient.transfer(amount);
    }

    /* ========== EVENTS ========== */

    event Reserved(address indexed user, uint256 project, uint256 amount);
}

