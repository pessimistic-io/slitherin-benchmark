// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "./CloneLibrary.sol";
import "./SafeERC20.sol";

/// @author YFLOW Team
/// @title UniV2LPFactory
/// @notice Factory contract to create new instances
contract UniV2LPFactory {
    using CloneLibrary for address;

    event NewUniV2LP(address uinv2LP, address cleint);
    event FactoryOwnerChanged(address newowner);
    event NewYieldManager(address newYieldManager);
    event NewUniV2LPImplementation(address newUniV2LPImplementation);
    event NewLPToken(address lptoken);
    event NewStakingTokenA(address stakingtokenA);
    event NewStakingTokenB(address stakingtokenB);
    event NewStakingContract(address stakingContract);
    event FeesWithdrawn(uint amount, address withdrawer);
    event NewSponsor(address sponsor, address client);

    address public factoryOwner;
    address public uniV2LPImplementation;
    address public yieldManager;
    address public lpToken;
    address public stakingTokenA;
    address public stakingTokenB;
    address public stakingContract;

    mapping(address => address) public stakingContractLookup;

    constructor(
        address _uniV2LPImplementation,
        address _yieldManager,
        address _lpToken,
        address _stakingTokenA,
        address _stakingTokenB,
        address _stakingContract
    )
    {
        require(_uniV2LPImplementation != address(0), "No zero address for _uniV2LPImplementation");
        require(_yieldManager != address(0), "No zero address for _yieldManager");

        factoryOwner = msg.sender;
        uniV2LPImplementation = _uniV2LPImplementation;
        yieldManager = _yieldManager;
        lpToken = _lpToken;
        stakingTokenA = _stakingTokenA;
        stakingTokenB = _stakingTokenB;
        stakingContract = _stakingContract;

        emit FactoryOwnerChanged(factoryOwner);
        emit NewUniV2LPImplementation(uniV2LPImplementation);
        emit NewYieldManager(yieldManager);
        emit NewLPToken(lpToken);
        emit NewStakingTokenA(stakingTokenA);
        emit NewStakingTokenB(stakingTokenB);
        emit NewStakingContract(stakingContract);
    }

    function uniV2LPMint(address sponsor)
    external
    returns(address uniV2)
    {
        uniV2 = uniV2LPImplementation.createClone();

        emit NewUniV2LP(uniV2, msg.sender);
        stakingContractLookup[msg.sender] = uniV2;

        IUinV2LPImplementation(uniV2).initialize(
            msg.sender,
            address(this)
        );

        if (sponsor != address(0) && sponsor != msg.sender && IYieldManager(yieldManager).getAffiliate(msg.sender) == address(0)) {
            IYieldManager(yieldManager).setAffiliate(msg.sender, sponsor);
            emit NewSponsor(sponsor, msg.sender);
        }
    }

    /**
     * @dev gets the address of the yield manager
     *
     * @return the address of the yield manager
    */
    function getYieldManager() external view returns (address) {
        return yieldManager;
    }

    function getLPToken() external view returns (address) {
        return lpToken;
    }

    function getStakingTokenA() external view returns (address) {
        return stakingTokenA;
    }

    function getStakingTokenB() external view returns (address) {
        return stakingTokenB;
    }

    function getStakingContract() external view returns (address) {
        return stakingContract;
    }

    /**
     * @dev lets the owner change the current uinv2 implementation
     *
     * @param uniV2LPImplementation_ the address of the new implementation
    */
    function newUniV2LPImplementation(address uniV2LPImplementation_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(uniV2LPImplementation_ != address(0), "No zero address for uniV2LPImplementation_");

        uniV2LPImplementation = uniV2LPImplementation_;
        emit NewUniV2LPImplementation(uniV2LPImplementation);
    }

    /**
     * @dev lets the owner change the current yieldManager_
     *
     * @param yieldManager_ the address of the new router
    */
    function newYieldManager(address yieldManager_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(yieldManager_ != address(0), "No zero address for yieldManager_");

        yieldManager = yieldManager_;
        emit NewYieldManager(yieldManager);
    }

    function newLPToken(address lpToken_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(lpToken_ != address(0), "No zero address for lpToken_");

        lpToken = lpToken_;
        emit NewLPToken(lpToken);
    }

    function newStakingTokenA(address stakingTokenA_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(stakingTokenA_ != address(0), "No zero address for stakingTokenA_");

        stakingTokenA = stakingTokenA_;
        emit NewStakingTokenA(stakingTokenA);
    }

    function newStakingTokenB(address stakingTokenB_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(stakingTokenB_ != address(0), "No zero address for stakingTokenB_");

        stakingTokenB = stakingTokenB_;
        emit NewStakingTokenB(stakingTokenB);
    }

    function newStakingContract(address stakingContract_) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(stakingContract_ != address(0), "No zero address for stakingContract_");

        stakingContract = stakingContract_;
        emit NewStakingContract(stakingContract);
    }

    /**
     * @dev lets the owner change the ownership to another address
     *
     * @param newOwner the address of the new owner
    */
    function newFactoryOwner(address payable newOwner) external {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(newOwner != address(0), "No zero address for newOwner");

        factoryOwner = newOwner;
        emit FactoryOwnerChanged(factoryOwner);
    }

    function getUserStakingContract(address staker) external view returns(address) {
        return stakingContractLookup[staker];
    }

    function withdrawRewardFees(
        address receiver,
        uint amount
    ) external  {
        require(msg.sender == factoryOwner, "Only factory owner");
        require(amount > 0, "Cannot withdraw 0");
        require(
            amount <= IERC20(lpToken).balanceOf(address(this)),
            "Cannot withdraw more than fees in the contract"
        );
        IERC20(lpToken).transfer(receiver, amount);
        emit FeesWithdrawn(amount, receiver);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) public payable returns (bytes memory) {
        require(
            msg.sender == factoryOwner,
            "executeTransaction: Call must come from owner"
        );

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(
            success,
            "executeTransaction: Transaction execution reverted."
        );

        return returnData;
    }

    /**
     * receive function to receive funds
    */
    receive() external payable {}
}

interface IUinV2LPImplementation {
    function initialize(
        address owner_,
        address factoryAddress_
    ) external;
}

interface IYieldManager {
    function setAffiliate(address client, address sponsor) external;
    function getAffiliate(address client) external view returns (address);
}


