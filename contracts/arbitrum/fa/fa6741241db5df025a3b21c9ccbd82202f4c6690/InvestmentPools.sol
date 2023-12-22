// SPDX-License-Identifier: MIT

// https://twitter.com/dealmpoker1
// https://discord.gg/hdgaZUqBSs
// https://t.me/+OZenwkiHEpliOGY0
// https://www.facebook.com/dealmpoker

pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./Initializable.sol";
import "./InvestmentPoolsStorage.sol";
import "./TokenSaleInterface.sol";

contract InvestmentPools is
    Initializable,
    OwnableUpgradeable,
    InvestmentPoolsStorage
{
    modifier onlyController() {
        require(controller[msg.sender] == true, "Caller is not controller");
        _;
    }

    modifier isDmpNftHolder() {
        require(
            IERC721(dmpNftContractAddress).balanceOf(msg.sender) > 0,
            "You don't hold DMP Nft"
        );
        _;
    }

    function createPool(
        uint256 amount,
        uint256 date,
        uint256 markUp,
        uint256 entryFee,
        string memory tournamentType,
        string memory description
    ) public isDmpNftHolder {
        require(date > block.timestamp, "The pool is expired!");
        require(
            markUp >= 1e18,
            "Markup should be greater than 1, or equal to 1"
        );
        require(
            bannedUsersMapping[msg.sender] == false,
            "Banned - You can't create a pool"
        );

        pools.push(
            Pools(
                msg.sender,
                amount,
                uint256(0),
                date,
                totalPools,
                markUp,
                tournamentType,
                description,
                false,
                false,
                false,
                false
            )
        );

        tournamentEntryFeePerPoolId[totalPools] = entryFee;

        uint256 toDlmPrice = amount *
            TokenSaleInterface(tokenSaleContractAddress).getPrice() *
            1e12;

        uint256 protocolFeeAmount = (toDlmPrice * protocolFeePercentage) / 100;

        IERC20(feeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            protocolFeeAmount
        );

        creatorFeePerPool[totalPools] = protocolFeeAmount;

        totalPools++;

        emit InvestmentPoolCreated(
            msg.sender,
            totalPools - 1,
            amount,
            block.timestamp,
            date,
            description
        );
    }

    function investInPool(uint256 poolId, uint256 amount) public {
        require(amount > 1e3, "Amount too low");
        require(
            amount + pools[poolId].amountRaised <= pools[poolId].targetAmount,
            "Amount too big"
        );
        require(
            pools[poolId].endTimestamp > block.timestamp,
            "The pool is expired!"
        );
        require(pools[poolId].claimed == false, "The pool is claimed!");
        require(pools[poolId].canceled == false, "The pool is canceled!");
        require(pools[poolId].validated == true, "The pool is not validated!");

        IERC20(paymentTokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        investorsPerPoolId[poolId].push(InvestorsPerPool(msg.sender, amount));
        investments.push(Investments(msg.sender, amount, poolId));
        userBalancePerPool[poolId][msg.sender] += amount;
        userHaveInvestedInPoolId[msg.sender][poolId] = true;

        pools[poolId].amountRaised += amount;

        emit PoolInvestment(msg.sender, poolId, amount, block.timestamp);
    }

    function removeInvestmentFromPool(uint256 poolId) public {
        require(
            userBalancePerPool[poolId][msg.sender] > 0,
            "You have not invested in this pool!"
        );
        require(pools[poolId].claimed == false, "The pool is already claimed!");
        require(
            pools[poolId].canceled == false,
            "The pool is already canceled!"
        );

        require(
            pools[poolId].endTimestamp < block.timestamp,
            "The pool is not expired!"
        );

        IERC20(paymentTokenAddress).transfer(
            msg.sender,
            userBalancePerPool[poolId][msg.sender]
        );
        pools[poolId].amountRaised -= userBalancePerPool[poolId][msg.sender];
        userBalancePerPool[poolId][msg.sender] = 0;
    }

    function claimAndCancelPool(uint256 poolId) public {
        require(
            pools[poolId].creator == msg.sender,
            "You are not the pool creator!"
        );
        require(pools[poolId].claimed == false, "The pool is already claimed!");
        require(
            pools[poolId].canceled == false,
            "The pool is already canceled!"
        );

        require(
            pools[poolId].endTimestamp > block.timestamp,
            "The pool is expired!"
        );
        require(pools[poolId].amountRaised > 0, "Pool is empty!");

        if (pools[poolId].amountRaised > 0) {
            IERC20(paymentTokenAddress).transfer(
                msg.sender,
                pools[poolId].amountRaised
            );
        }

        pools[poolId].claimed = true;
        pools[poolId].canceled = true;

        emit PoolClaimed(
            msg.sender,
            poolId,
            pools[poolId].amountRaised,
            block.timestamp
        );
    }

    function cancelPool(uint256 poolId) public {
        require(
            pools[poolId].creator == msg.sender,
            "You are not the pool creator!"
        );
        require(
            pools[poolId].canceled == false,
            "The pool is already canceled!"
        );
        require(pools[poolId].validated == false, "Can't cancel valid pool!");
        require(pools[poolId].rejected == false, "Can't cancel rejected pool!");

        IERC20(feeTokenAddress).transfer(msg.sender, creatorFeePerPool[poolId]);

        pools[poolId].canceled = true;

        emit PoolCanceled(
            msg.sender,
            poolId,
            creatorFeePerPool[poolId],
            block.timestamp
        );
    }

    function setProfileDescription(
        address to,
        string memory profileDesc
    ) public isDmpNftHolder {
        require(msg.sender == to, "You can't set profile description");
        profileDescription[to] = profileDesc;
    }

    function setProfilePicture(
        address to,
        string memory profilePic
    ) public isDmpNftHolder {
        require(msg.sender == to, "You can't set profile picture");
        profilePicture[to] = profilePic;
    }

    function validatePool(uint256 poolId) external virtual onlyController {
        require(!pools[poolId].validated, "Already validated!");

        IERC20(feeTokenAddress).transfer(
            protocolFeeReceiver,
            creatorFeePerPool[poolId]
        );

        pools[poolId].validated = true;
    }

    function rejectPool(uint256 poolId) external virtual onlyController {
        require(!pools[poolId].rejected, "Already rejected!");
        require(!pools[poolId].validated, "Already validated!");
        require(!pools[poolId].canceled, "Already canceled!");
        require(!pools[poolId].claimed, "Already claimed!");

        IERC20(feeTokenAddress).transfer(
            pools[poolId].creator,
            creatorFeePerPool[poolId]
        );

        pools[poolId].rejected = true;
    }

    function getUserBalancePerPool(
        address addr,
        uint256 poolId
    ) external view override returns (uint256) {
        return userBalancePerPool[poolId][addr];
    }

    function getAmountRaisedPerPool(
        uint256 poolId
    ) external view override returns (uint256) {
        return pools[poolId].amountRaised;
    }

    function creatorPerPoolId(
        uint256 poolId
    ) external view override returns (address) {
        return pools[poolId].creator;
    }

    function checkIfUserHasInvestedInPoolId(
        address user,
        uint256 poolId
    ) external view override returns (bool) {
        return userHaveInvestedInPoolId[user][poolId];
    }

    function setDmpNftContractAddress(
        address newDmpNftContractAddress
    ) external virtual onlyController {
        dmpNftContractAddress = newDmpNftContractAddress;
    }

    function setTokenSaleContractAddress(
        address _newTokenSaleContractAddress
    ) external virtual onlyController {
        tokenSaleContractAddress = _newTokenSaleContractAddress;
    }

    function setFeeTokenAddress(
        address _newFeeTokenAddress
    ) external virtual onlyController {
        feeTokenAddress = _newFeeTokenAddress;
    }

    function setPaymentTokenAddress(
        address _newPaymentTokenAddress
    ) external virtual onlyController {
        paymentTokenAddress = _newPaymentTokenAddress;
    }

    function setProtocolFeeReceiver(
        address _newProtocolFeeReceiver
    ) external virtual onlyController {
        protocolFeeReceiver = _newProtocolFeeReceiver;
    }

    function setProtocolFeePercentage(
        uint256 _newProtocolFeePercentage
    ) external virtual onlyController {
        protocolFeePercentage = _newProtocolFeePercentage;
    }

    function banUnban(
        address _addr,
        bool _value
    ) external virtual onlyController {
        bannedUsersMapping[_addr] = _value;
    }

    function setController(
        address _addr,
        bool _value
    ) external virtual onlyOwner {
        controller[_addr] = _value;
    }
}

