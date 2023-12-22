// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IPlatformFee.sol";
import "./ICalamus.sol";
import "./Types.sol";
import "./CarefulMath.sol";

import "./interfaces_IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./EnumerableMapUpgradeable.sol";

contract Calamus is Initializable, OwnableUpgradeable, ICalamus, IPlatformFee, ReentrancyGuardUpgradeable, CarefulMath, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;
    uint256 public nextStreamId;
    uint32 constant private DENOMINATOR = 10000;

    mapping (address => uint256) public ownerToStreams;
    mapping (address => uint256) public recipientToStreams;
    mapping (uint256 => Types.Stream) public streams;
    mapping (address => uint256) private contractFees;
    mapping (address => uint32) private withdrawFeeAddresses;
    address[] private withdrawAddresses;

    EnumerableMapUpgradeable.AddressToUintMap addressFees;
    uint32 public rateFee;

    mapping (address => address[]) private availableTokens;
    mapping (address => mapping (address => uint256)) private userTokenBalance;
    mapping (address => mapping (address => uint256)) private lockedUserTokenBalance;

    address private systemAddress;

    function initialize(uint32 initialFee) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        rateFee = initialFee;
        nextStreamId = 1;
    }

    modifier isAllowAddress(address allowAddress) {
        require(allowAddress != address(0x00), "Address 0");
        require(allowAddress != address(this), "address(this)");
        _;
    }

    modifier streamExists(uint256 streamId) {
        require(streams[streamId].streamId >= 0, "stream does not exist");
        _;
    }



    function setRateFee(uint32 newRateFee) public override onlyOwner {
        rateFee = newRateFee;
        emit SetRateFee(newRateFee);
    }

    function deltaOf(uint256 streamId) public view streamExists(streamId) returns (uint256 delta) {
        Types.Stream memory stream = streams[streamId];
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp < stream.stopTime) return block.timestamp - stream.startTime;
        return stream.stopTime - stream.startTime;
    }

    struct FeeVars {
        bool exists;
        uint256 value;
    }

    function feeOf(address userAddress, address tokenAddress) external view returns (uint256 fee) {
        return _feeOf(userAddress, tokenAddress);
    }

    function _feeOf(address userAddress, address tokenAddress) private view returns (uint256 fee) {
        FeeVars memory vars;
        (vars.exists, vars.value) = addressFees.tryGet(userAddress);
        if (vars.exists) {
            return vars.value;
        }
        (vars.exists, vars.value) = addressFees.tryGet(tokenAddress);
        if (vars.exists) {
            return vars.value;
        }
        return uint256(rateFee);
    }

    struct BalanceOfLocalVars {
        MathError mathErr;
        uint256 recipientBalance;
        uint256 releaseTimes;
        uint256 withdrawalAmount;
        uint256 senderBalance;
    }

    function balanceOf(uint256 streamId, address who) public override view streamExists(streamId) returns (uint256 balance) {
        Types.Stream memory stream = streams[streamId];
        BalanceOfLocalVars memory vars;

        uint256 delta = deltaOf(streamId);
        (vars.mathErr, vars.releaseTimes) = divUInt(delta, stream.releaseFrequency);
        uint256 duration = stream.stopTime - stream.startTime;

        if (delta == duration) {
            vars.recipientBalance = stream.releaseAmount;
        } else if (vars.releaseTimes > 0 && vars.mathErr == MathError.NO_ERROR) {
            (vars.mathErr, vars.recipientBalance) = mulUInt(stream.releaseFrequency * vars.releaseTimes, stream.releaseAmount);
            if (vars.mathErr == MathError.NO_ERROR) {
                vars.recipientBalance /= duration;
            } else {
                (vars.mathErr, vars.recipientBalance) = mulUInt(stream.releaseFrequency * vars.releaseTimes, stream.releaseAmount / duration);
            }
        }

        if (stream.vestingAmount > 0 && delta > 0) {
            vars.recipientBalance += stream.vestingAmount;
        }

        require(vars.mathErr == MathError.NO_ERROR, "recipient balance calculation error");

        /*
         * If the stream `balance` does not equal `deposit`, it means there have been withdrawals.
         * We have to subtract the total amount withdrawn from the amount of money that has been
         * streamed until now.
         */
        uint256 totalRelease = stream.releaseAmount + stream.vestingAmount;
        if (totalRelease > stream.remainingBalance) {
            (vars.mathErr, vars.withdrawalAmount) = subUInt(totalRelease, stream.remainingBalance);
            assert(vars.mathErr == MathError.NO_ERROR);
            (vars.mathErr, vars.recipientBalance) = subUInt(vars.recipientBalance, vars.withdrawalAmount);
            /* `withdrawalAmount` cannot and should not be bigger than `recipientBalance`. */
            assert(vars.mathErr == MathError.NO_ERROR);
        }

        if (who == stream.recipient) return vars.recipientBalance;
        if (who == stream.sender) {
            (vars.mathErr, vars.senderBalance) = subUInt(stream.remainingBalance, vars.recipientBalance);
            /* `recipientBalance` cannot and should not be bigger than `remainingBalance`. */
            assert(vars.mathErr == MathError.NO_ERROR);
            return vars.senderBalance;
        }
        return 0;
    }

    struct CreateStreamLocalVars {
        MathError mathErr;
        uint256 duration;
        uint256 vestingAmount;
    }

    function _validateGeneralInfo(Types.StreamGeneral memory generalInfo,  uint256 blockTimestamp, CreateStreamLocalVars memory vars) internal pure {
        require(generalInfo.startTime >= blockTimestamp, "start time before block.timestamp");
        require(generalInfo.stopTime > generalInfo.startTime, "stop time before the start time");

        require(generalInfo.vestingRelease <= DENOMINATOR, "vesting release is too much");
        require(generalInfo.releaseFrequency > 0, "release frequency is zero");
        (vars.mathErr, vars.duration) = subUInt(generalInfo.stopTime, generalInfo.startTime);
        /* `subUInt` can only return MathError.INTEGER_UNDERFLOW but we know `stopTime` is higher than `startTime`. */
        if (vars.mathErr != MathError.NO_ERROR) {
            revert("Math Error!");
        }
        require(vars.duration >= generalInfo.releaseFrequency, "Duration is smaller than frequency");
    }

    function _validateRecipient(
        Types.Recipient memory recipient,
        address addressZero,
        address addressThis,
        address sender
    ) internal pure {
        require(recipient.recipient != addressZero, "Address 0");
        require(recipient.recipient != addressThis, "address(this)");
        require(recipient.recipient != sender, "is sender");
        require(recipient.releaseAmount > 0, "releaseAmount=0");
    }

    function _validateAllStreams(
        Types.StreamGeneral memory generalInfo,
        Types.Recipient[] memory recipients,
        address correctTokenAddress,
        CreateStreamLocalVars memory vars
    ) internal view {
        require(recipients.length > 0, "!Stream.length");
        Types.Recipient memory recipient;
        uint256 blockTimestamp = block.timestamp;
        address addressZero = address(0);
        address addressThis = address(this);
        address sender = msg.sender;
        uint256 totalAmount = 0;
        _validateGeneralInfo(
            generalInfo,
            blockTimestamp,
            vars
        );
        for (uint i=0; i < recipients.length; i++) {
            recipient= recipients[i];
            _validateRecipient(
                recipient,
                addressZero,
                addressThis,
                sender
            );
            totalAmount += recipient.releaseAmount;
        }

        uint256 totalReleaseAmountIncludeFee = _getAmountIncludedFee(
            sender,
            generalInfo.tokenAddress,
            totalAmount
        );

        require(
            (userTokenBalance[msg.sender][correctTokenAddress] - lockedUserTokenBalance[msg.sender][correctTokenAddress]) >= totalReleaseAmountIncludeFee,
            "balance-lockedAmount<totalReleaseAmountIncludeFee"
        );
    }


    function _createBatchStreams(Types.StreamGeneral memory generalInfo, Types.Recipient[] memory recipients) internal {
        CreateStreamLocalVars memory vars;

        address correctTokenAddress = (generalInfo.tokenAddress == address(this)) ? address(0) : generalInfo.tokenAddress;

        _validateAllStreams(generalInfo, recipients, correctTokenAddress, vars);

        Types.RecipientResponse[] memory recipientsResponse = new Types.RecipientResponse[](recipients.length);

        Types.Stream memory stream;

        Types.Recipient memory recipient;

        address sender = msg.sender;

        uint totalReleaseAmount = 0;

        for (uint i=0; i < recipients.length; i++) {
            recipient = recipients[i];
            totalReleaseAmount += recipient.releaseAmount;

            (vars.mathErr, vars.vestingAmount) = mulUInt(recipient.releaseAmount, generalInfo.vestingRelease);

            assert(vars.mathErr == MathError.NO_ERROR);

            vars.vestingAmount /= DENOMINATOR;

            stream = Types.Stream(
                nextStreamId + i,
                sender,
                recipient.releaseAmount - vars.vestingAmount,
                recipient.releaseAmount,
                generalInfo.startTime,
                generalInfo.stopTime,
                vars.vestingAmount,
                generalInfo.releaseFrequency,
                generalInfo.transferPrivilege,
                generalInfo.cancelPrivilege,
                recipient.recipient,
                correctTokenAddress,
                1
            );
            streams[nextStreamId + i] = stream;

            recipientsResponse[i] = Types.RecipientResponse(
                nextStreamId + i,
                recipient.recipient,
                stream.releaseAmount
            );
        }


        uint256 totalReleaseAmountIncludeFee = _getAmountIncludedFee(
            sender,
            generalInfo.tokenAddress,
            totalReleaseAmount
        );

        contractFees[correctTokenAddress] += totalReleaseAmountIncludeFee - totalReleaseAmount;

        lockedUserTokenBalance[sender][correctTokenAddress] += totalReleaseAmount;

        userTokenBalance[sender][correctTokenAddress] -= totalReleaseAmountIncludeFee - totalReleaseAmount;

        ownerToStreams[sender] += recipients.length;

        recipientToStreams[recipient.recipient] += recipients.length;

        /* Increment the next stream id. */
        nextStreamId += recipients.length;
        Types.StreamGeneralResponse memory generalInfoResponse = Types.StreamGeneralResponse(
            sender,
            correctTokenAddress,
            generalInfo.startTime,
            generalInfo.stopTime,
            generalInfo.vestingRelease,
            generalInfo.releaseFrequency,
            generalInfo.transferPrivilege,
            generalInfo.cancelPrivilege
        );
        emit BatchStreams(
            generalInfoResponse,
            recipientsResponse
        );
    }

    function _getAmountIncludedFee(address sender, address tokenAddress, uint256 amount) internal view returns (uint256) {
        uint256 fee = _feeOf(sender, tokenAddress);
        uint256 amountIncludedFee = (amount * (DENOMINATOR + fee) / DENOMINATOR);
        return amountIncludedFee;
    }

    function _transferFrom(address tokenAddress, uint256 releaseAmount) internal {
        IERC20Upgradeable(tokenAddress).transferFrom(msg.sender, address(this), releaseAmount);
    }

    function _transfer(address tokenAddress, address to, uint256 amount) internal {
        IERC20Upgradeable(tokenAddress).transfer(to, amount);
    }

    function getOwnerToStreams(address owner) public view returns (Types.Stream[] memory) {
        uint256 streamCount = 0;
        Types.Stream[] memory filterStreams = new Types.Stream[](ownerToStreams[owner]);

        for (uint i=1; i < nextStreamId; i++) {
            if (streams[i].sender == owner) {
                filterStreams[streamCount] = streams[i];
                streamCount++;
            }
        }
        return filterStreams;
    }

    function getRecipientToStreams(address recipient) public view returns (Types.Stream[] memory) {
        uint256 streamCount = 0;
        Types.Stream[] memory filterStreams = new Types.Stream[](recipientToStreams[recipient]);

        for (uint i=1; i < nextStreamId; i++) {
            if (streams[i].recipient == recipient) {
                filterStreams[streamCount] = streams[i];
                streamCount++;
            }
        }
        return filterStreams;
    }

    function withdrawFromStream(uint256 streamId, uint256 amount)
    public
    override
    whenNotPaused
    nonReentrant
    streamExists(streamId)
    {
        Types.Stream memory stream = streams[streamId];
        require(amount > 0, "amount=0");
        require(stream.status == 1, "!active");
        require(stream.recipient == msg.sender, "!recipient");
        uint256 balance = balanceOf(streamId, stream.recipient);
        require(balance >= amount, "balance<amount");

        streams[streamId].remainingBalance -= amount;

        if (streams[streamId].remainingBalance == 0) {
            streams[streamId].status = 3;
        }

        userTokenBalance[stream.sender][stream.tokenAddress] -= amount;
        lockedUserTokenBalance[stream.sender][stream.tokenAddress] -= amount;


        if (stream.tokenAddress != address(0x00)) {
            _transfer(stream.tokenAddress, stream.recipient, amount );
        } else {
            payable(stream.recipient).transfer(amount);
        }

        emit WithdrawFromStream(streamId, stream.recipient, amount);
    }

    function _checkCancelPermission(Types.Stream memory stream) internal view returns (bool) {
        address sender = msg.sender;
        address streamSender = stream.sender;
        address recipient = stream.recipient;
        if (stream.cancelPrivilege == 0) {
            return (sender == recipient);
        } else if (stream.cancelPrivilege == 1) {
            return (sender == streamSender);
        } else if (stream.cancelPrivilege == 2) {
            return true;
        } else if (stream.cancelPrivilege == 3) {
            return false;
        } else {
            return false;
        }
    }

    function _checkTransferPermission(Types.Stream memory stream) internal view returns (bool) {
        address sender = msg.sender;
        address streamSender = stream.sender;
        address recipient = stream.recipient;
        if (stream.transferPrivilege == 0) {
            return (sender == recipient);
        } else if (stream.transferPrivilege == 1) {
            return (sender == streamSender);
        } else if (stream.transferPrivilege == 2) {
            return true;
        } else if (stream.transferPrivilege == 3) {
            return false;
        } else {
            return false;
        }
    }

    function cancelStream(uint256 streamId)
    public
    override
    whenNotPaused
    nonReentrant
    streamExists(streamId)
    {
        Types.Stream memory stream = streams[streamId];
        require(stream.status == 1, "!active");
        require(_checkCancelPermission(stream), "!permission");
        uint256 senderBalance = balanceOf(streamId, stream.sender);
        uint256 recipientBalance = balanceOf(streamId, stream.recipient);

        streams[streamId].status = 2;

        IERC20Upgradeable token = IERC20Upgradeable(stream.tokenAddress);

        if (recipientBalance > 0) {
            streams[streamId].remainingBalance -= recipientBalance;
            userTokenBalance[stream.sender][stream.tokenAddress] -= recipientBalance;
            lockedUserTokenBalance[stream.sender][stream.tokenAddress] -= recipientBalance;

            if (stream.tokenAddress != address(0x00)) {

                token.transfer(stream.recipient, recipientBalance);

            } else {

                payable(stream.recipient).transfer(recipientBalance);

            }

        }

        emit CancelStream(streamId, stream.sender, stream.recipient, senderBalance, recipientBalance);
    }

    function _changeStreamRecipient(uint256 streamId, address newRecipient) internal {
        Types.Stream memory stream = streams[streamId];
        recipientToStreams[stream.recipient] -= 1;
        recipientToStreams[newRecipient] += 1;
        streams[streamId].recipient = newRecipient;
    }

    function transferStream(uint256 streamId, address newRecipient)
    public
    override
    whenNotPaused
    nonReentrant
    streamExists(streamId) {
        Types.Stream memory stream = streams[streamId];
        require(stream.status == 1, "!active");
        require(_checkTransferPermission(stream), "!permission");
        require(newRecipient != stream.recipient, "New=Old");
        require(newRecipient != address(0x00), "Address 0");
        require(newRecipient != address(this), "address(this)");
        require(newRecipient != msg.sender, "recipient=sender");
        uint256 recipientBalance = balanceOf(streamId, stream.recipient);

        _changeStreamRecipient(streamId, newRecipient);

        if (recipientBalance > 0) {
            streams[streamId].remainingBalance -= recipientBalance;
            userTokenBalance[stream.sender][stream.tokenAddress] -= recipientBalance;
            lockedUserTokenBalance[stream.sender][stream.tokenAddress] -= recipientBalance;

            if (stream.tokenAddress != address(0x00)) {

                _transfer(stream.tokenAddress, stream.recipient, recipientBalance );

            } else {

                payable(stream.recipient).transfer(recipientBalance);

            }
        }

        emit TransferStream(streamId, stream.sender, newRecipient, recipientBalance);
    }
    
    function topupStream(uint256 streamId, uint256 amount)
        public
        override
        whenNotPaused
        nonReentrant
        streamExists(streamId)
    {
        Types.Stream memory stream = streams[streamId];

        uint256 amountIncludeFee = _getAmountIncludedFee(
            msg.sender,
            stream.tokenAddress == address(0x00) ? address(this) : stream.tokenAddress,
            amount
        );

        require((userTokenBalance[msg.sender][stream.tokenAddress] - lockedUserTokenBalance[msg.sender][stream.tokenAddress]) >= amountIncludeFee, "balance-lockedAmount<amountIncludeFee" );

        require(stream.status == 1, "!active");
        require(stream.sender == msg.sender, "!permission");
        require(amount > 0, "Amount=0");
        require(block.timestamp < stream.stopTime, "Ended");

        streams[streamId].releaseAmount += amount;
        streams[streamId].remainingBalance += amount;
        streams[streamId].stopTime =
            stream.stopTime +
            (amount * (stream.stopTime - stream.startTime)) /
            stream.releaseAmount;

        contractFees[stream.tokenAddress] += amountIncludeFee - amount;
        userTokenBalance[msg.sender][stream.tokenAddress] -= amountIncludeFee - amount;
        lockedUserTokenBalance[msg.sender][stream.tokenAddress] += amount;

        emit TopupStream(streamId, amount, streams[streamId].stopTime);
    }

    function addWithdrawFeeAddress(address allowAddress, uint32 percentage) public override onlyOwner isAllowAddress(allowAddress) {
        require(percentage > 0, "Percentage=0");
        withdrawFeeAddresses[allowAddress] = percentage;
        withdrawAddresses.push(allowAddress);
        emit AddWithdrawFeeAddress(allowAddress, percentage);
    }

    function removeWithdrawFeeAddress(address allowAddress) public override onlyOwner returns(bool) {
        uint32 percentage = withdrawFeeAddresses[allowAddress];
        if (percentage > 0) {
            delete withdrawFeeAddresses[allowAddress];
            for (uint32 i = 0; i < withdrawAddresses.length; i++) {
                if (withdrawAddresses[i] == allowAddress) {
                    delete withdrawAddresses[i];
                    break;
                }
            }
            emit RemoveWithdrawFeeAddress(allowAddress);
            return true;
        }
        return false;
    }

    function getWithdrawFeeAddresses() public override view onlyOwner returns(Types.WithdrawFeeAddress[] memory) {

        Types.WithdrawFeeAddress[] memory addresses = new Types.WithdrawFeeAddress[](withdrawAddresses.length);

        for (uint32 i=0; i< withdrawAddresses.length; i++ ) {
            addresses[i] = Types.WithdrawFeeAddress(
                withdrawAddresses[i],
                withdrawFeeAddresses[withdrawAddresses[i]]
            );
        }
        return addresses;
    }

    function isAllowWithdrawingFee(address allowAddress) public override view onlyOwner returns (bool) {
        uint32 percentage = withdrawFeeAddresses[allowAddress];
        if (percentage > 0) {
            return true;
        }
        return false;
    }

    function getContractFee(address tokenAddress) public override view returns(uint256) {
        if (tokenAddress == address(this)) {
            return contractFees[address(0)];
        }
        return contractFees[tokenAddress];
    }

    function withdrawFee(address to, address tokenAddress, uint256 amount) public override whenNotPaused nonReentrant onlyOwner  returns(bool) {
        uint256 feeBalance = contractFees[(tokenAddress == address(this))? address(0x00) : tokenAddress];

        require(isAllowWithdrawingFee(to), "!allowing");
        require(to != address(this), "address(this)");
        require(feeBalance >= amount, "feeBalance < amount");

        uint256 allowAmount = (feeBalance * withdrawFeeAddresses[to] / 100);
        require(amount <= allowAmount, "amount > allowAmount");
        if (tokenAddress != address(this)) {

            _transfer(tokenAddress, to, amount );

        } else {
            payable(to).transfer(amount);
        }
        emit WithdrawFee(tokenAddress, to, amount);
        return true;
    }

    function pause() public onlyOwner {
        _pause();
    }
    function unpause() public onlyOwner {
        _unpause();
    }

    function addWhitelistAddress(address whitelistAddress, uint256 fee) public onlyOwner {
        addressFees.set(whitelistAddress, fee);
    }

    function removeWhitelistAddress(address whitelistAddress) public onlyOwner {
        addressFees.remove(whitelistAddress);
    }

    function deposit(address tokenAddress, uint256 amount) external payable whenNotPaused nonReentrant {
        require(amount > 0, "Amount<=0");
        require(tokenAddress != address(0x00), "Address 0");
        address correctTokenAddress = (tokenAddress == address(this)) ? address(0x00) : tokenAddress;
        userTokenBalance[msg.sender][correctTokenAddress] += amount;

        bool checkTokenExist = false;
        address[] memory tokens = availableTokens[msg.sender];
        for(uint i=0; i < tokens.length; i++) {
            if (tokens[i] == correctTokenAddress) {
                checkTokenExist = true;
            }
        }

        if (!checkTokenExist) {
            availableTokens[msg.sender].push(correctTokenAddress);
        }

        if (tokenAddress != address(this)) {
            _transferFrom(tokenAddress, amount);
        }

        emit Deposit(msg.sender, tokenAddress, amount);
    }

    function withdrawFromBalance(address tokenAddress, uint256 amount) external whenNotPaused nonReentrant {
        address correctTokenAddress = (tokenAddress == address(this)) ? address(0) : tokenAddress;
        require(userTokenBalance[msg.sender][correctTokenAddress] > 0, "balance=0");
        require(userTokenBalance[msg.sender][correctTokenAddress] - lockedUserTokenBalance[msg.sender][correctTokenAddress] >= amount, "Available balance < amount");
        userTokenBalance[msg.sender][correctTokenAddress] -= amount;
        if (tokenAddress != address(this)) {

            _transfer(correctTokenAddress, msg.sender, amount );

        } else {
            payable(msg.sender).transfer(amount);
        }

        emit WithdrawFromBalance(msg.sender, amount);

    }

    function batchStreams(Types.StreamGeneral memory generalInfo, Types.Recipient[] memory recipients) external whenNotPaused nonReentrant {
        _createBatchStreams(generalInfo, recipients);
    }

    function getUserTokenBalance(address tokenAddress) external view returns (uint256) {
        address correctTokenAddress = (tokenAddress == address(this)) ? address(0x00) : tokenAddress;
        uint256 balance = userTokenBalance[msg.sender][correctTokenAddress];
        return balance;
    }

    function getAllUserTokenBalance() external view returns (Types.TokenBalance[] memory) {
        address[] memory tokens = availableTokens[msg.sender];
        Types.TokenBalance[] memory tokenBalances = new Types.TokenBalance[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            tokenBalances[i] = Types.TokenBalance(
                tokens[i],
                userTokenBalance[msg.sender][tokens[i]]
            );
        }
        return tokenBalances;
    }

    function getUserLockedTokenBalance(address tokenAddress) external view returns (uint256) {
        address correctTokenAddress = (tokenAddress == address(this)) ? address(0x00) : tokenAddress;
        uint256 balance = lockedUserTokenBalance[msg.sender][correctTokenAddress];
        return balance;
    }

    function getAllUserLockedTokenBalance() external view returns (Types.TokenBalance[] memory) {
        address[] memory tokens = availableTokens[msg.sender];
        Types.TokenBalance[] memory tokenBalances = new Types.TokenBalance[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            tokenBalances[i] = Types.TokenBalance(
                tokens[i],
                lockedUserTokenBalance[msg.sender][tokens[i]]
            );
        }
        return tokenBalances;
    }

    function getDueDateStreams() public view whenNotPaused returns (Types.Stream[] memory) {
        require(msg.sender == systemAddress, "!system address");
        return _getDueDateStreams();
    }
    function _getDueDateStreams() internal view returns (Types.Stream[] memory) {
        uint currentTimeStamp = block.timestamp;
        Types.Stream memory currentStream;
        Types.Stream[] memory dueStreams = new Types.Stream[](nextStreamId);
        uint count = 0;
        for (uint i=1; i < nextStreamId; i++) {
            currentStream = streams[i];
            if (currentStream.status == 1 && currentStream.stopTime < currentTimeStamp && currentStream.remainingBalance > 0 ) {
                dueStreams[i] = streams[i];
                dueStreams[i].streamId = i;
                count += 1;
            }
        }
        Types.Stream[] memory correctDueDateStreams = new Types.Stream[](count);
        count = 0;
        for (uint i=0; i < nextStreamId; i++) {
            if (dueStreams[i].streamId != 0) {
                correctDueDateStreams[count] = dueStreams[i];
                count += 1;
            }

        }

        return correctDueDateStreams;
    }

    function doAutoWithdraw(uint256[] memory streamIds) external {
        require(msg.sender == systemAddress, "!system address");
        if (streamIds.length > 0) {
            Types.Stream memory stream;
            for(uint i=0; i < streamIds.length; i++) {
                uint streamId = streamIds[i];
                stream = streams[streamId];

                if (userTokenBalance[stream.sender][stream.tokenAddress] >= stream.remainingBalance && lockedUserTokenBalance[stream.sender][stream.tokenAddress] >= stream.remainingBalance) {

                    userTokenBalance[stream.sender][stream.tokenAddress] -= stream.remainingBalance;

                    lockedUserTokenBalance[stream.sender][stream.tokenAddress] -= stream.remainingBalance;

                }

                streams[streamId].remainingBalance = 0;
                streams[streamId].status = 3;
                if (stream.tokenAddress != address(0x00)) {
                    _transfer(stream.tokenAddress, stream.recipient, stream.remainingBalance );
                } else {
                    payable(stream.recipient).transfer(stream.remainingBalance);
                }
            }

            emit DoAutoWithdraw(msg.sender, streamIds);
        }
    }

    function getSystemAddress() external view onlyOwner returns (address) {
        return systemAddress;
    }

    function setSystemAddress(address newSystemAddress) external onlyOwner {
        require(systemAddress != newSystemAddress, "New=Old");
        systemAddress = newSystemAddress;
        emit SetSystemAddress(msg.sender, newSystemAddress);
    }

    function batchTransfer(address tokenAddress, address[] calldata recipients, uint256[] calldata values) external whenNotPaused nonReentrant {
        address correctTokenAddress = (tokenAddress == address(this)) ? address(0) : tokenAddress;
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += values[i];
        }
        uint256 totalAmountIncludeFee = _getAmountIncludedFee(
            msg.sender,
            tokenAddress,
            total
        );
        require(
            (userTokenBalance[msg.sender][correctTokenAddress] - lockedUserTokenBalance[msg.sender][correctTokenAddress]) >= totalAmountIncludeFee,
            "balance-lockedAmount<totalAmountIncludeFee"
        );
        contractFees[correctTokenAddress] += totalAmountIncludeFee - total;
        userTokenBalance[msg.sender][correctTokenAddress] -= totalAmountIncludeFee;

        if (tokenAddress == address(this)) {
            for (uint256 i = 0; i < recipients.length; i++) {
                payable(recipients[i]).transfer(values[i]);
            }
        } else {
            for (uint256 i = 0; i < recipients.length; i++) {
                _transfer(correctTokenAddress, recipients[i], values[i]);
            }
        }
    }
}
