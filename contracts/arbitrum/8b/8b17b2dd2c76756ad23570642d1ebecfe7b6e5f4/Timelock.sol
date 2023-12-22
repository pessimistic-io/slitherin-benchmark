// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./console.sol";

contract Timelock is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct Items {
        address tokenAddress;
        address withdrawalAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
    }

    uint256 public depositId;
    uint256[] public allDepositIds;
    mapping(address => uint256[]) public depositsByWithdrawalAddress;
    mapping(address => uint256[]) public depositsByTokenAddress;
    mapping(uint256 => Items) public lockedToken;
    mapping(address => mapping(address => uint256)) public walletTokenBalance;

    event TokensLocked(
        address indexed tokenAddress, address indexed sender, uint256 amount, uint256 unlockTime, uint256 depositId
    );
    event TokensWithdrawn(address indexed tokenAddress, address indexed receiver, uint256 amount);

    /* ──────────────────────────CONSTRUCTOR──────────────────────────────────*/
    constructor() { }

    /* ─────────────────────PERIPHERALS───────────────────────────────────────*/
    receive() external payable {
        // ...
    }

    fallback() external {
        // ...
    }

    /* ─────────────────────EXTERNAL FUNCTIONS───────────────────────────────────────*/

    /* ─────────────────────EXTERNAL FUNCTIONS THAT ARE VIEW───────────────────────────────────────*/

    /* ─────────────────────EXTERNAL FUNCTIONS THAT ARE PURE───────────────────────────────────────*/

    /* ─────────────────────PUBLIC FUNCTIONS───────────────────────────────────────*/
    function lockTokens(address _tokenAddress, uint256 _amount, uint256 _unlockTime) external returns (uint256 _id) {
        require(_amount > 0, "Tokens amount must be greater than 0");
        require(_unlockTime < 10_000_000_000, "Unix timestamp must be in seconds, not milliseconds");
        require(_unlockTime > block.timestamp, "Unlock time must be in future");

        require(ERC20(_tokenAddress).approve(address(this), _amount), "Failed to approve tokens");
        require(
            ERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount), "Failed to transfer tokens to locker"
        );

        uint256 lockAmount = _amount;

        walletTokenBalance[_tokenAddress][msg.sender] = walletTokenBalance[_tokenAddress][msg.sender].add(_amount);

        address _withdrawalAddress = msg.sender;
        _id = ++depositId;
        lockedToken[_id].tokenAddress = _tokenAddress;
        lockedToken[_id].withdrawalAddress = _withdrawalAddress;
        lockedToken[_id].tokenAmount = lockAmount;
        lockedToken[_id].unlockTime = _unlockTime;
        lockedToken[_id].withdrawn = false;

        allDepositIds.push(_id);
        depositsByWithdrawalAddress[_withdrawalAddress].push(_id);
        depositsByTokenAddress[_tokenAddress].push(_id);

        emit TokensLocked(_tokenAddress, msg.sender, _amount, _unlockTime, depositId);
    }

    // TODO:
    // function status(uint256 _depositId) public onlyOwner {
    //     lockedToken[_depositId].unlockTime = block.timestamp;
    // }

    function withdrawTokens(uint256 _id) external payable {
        require(block.timestamp >= lockedToken[_id].unlockTime, "Tokens are locked");
        require(!lockedToken[_id].withdrawn, "Tokens already withdrawn");
        require(msg.sender == lockedToken[_id].withdrawalAddress, "Can withdraw from the address used for locking");

        address tokenAddress = lockedToken[_id].tokenAddress;
        address withdrawalAddress = lockedToken[_id].withdrawalAddress;
        uint256 amount = lockedToken[_id].tokenAmount;

        require(ERC20(tokenAddress).transfer(withdrawalAddress, amount), "Failed to transfer tokens");

        lockedToken[_id].withdrawn = true;
        uint256 previousBalance = walletTokenBalance[tokenAddress][msg.sender];
        walletTokenBalance[tokenAddress][msg.sender] = previousBalance.sub(amount);

        // Remove depositId from withdrawal addresses mapping
        uint256 i;
        uint256 j;
        uint256 byWLength = depositsByWithdrawalAddress[withdrawalAddress].length;
        uint256[] memory newDepositsByWithdrawal = new uint256[](byWLength - 1);

        for (j = 0; j < byWLength; j++) {
            if (depositsByWithdrawalAddress[withdrawalAddress][j] == _id) {
                for (i = j; i < byWLength - 1; i++) {
                    newDepositsByWithdrawal[i] = depositsByWithdrawalAddress[withdrawalAddress][i + 1];
                }
                break;
            } else {
                newDepositsByWithdrawal[j] = depositsByWithdrawalAddress[withdrawalAddress][j];
            }
        }
        depositsByWithdrawalAddress[withdrawalAddress] = newDepositsByWithdrawal;

        // Remove depositId from tokens mapping
        uint256 byTLength = depositsByTokenAddress[tokenAddress].length;
        uint256[] memory newDepositsByToken = new uint256[](byTLength - 1);
        for (j = 0; j < byTLength; j++) {
            if (depositsByTokenAddress[tokenAddress][j] == _id) {
                for (i = j; i < byTLength - 1; i++) {
                    newDepositsByToken[i] = depositsByTokenAddress[tokenAddress][i + 1];
                }
                break;
            } else {
                newDepositsByToken[j] = depositsByTokenAddress[tokenAddress][j];
            }
        }
        depositsByTokenAddress[tokenAddress] = newDepositsByToken;

        emit TokensWithdrawn(tokenAddress, withdrawalAddress, amount);
    }

    function getTotalTokenBalance(address _tokenAddress) public view returns (uint256) {
        return ERC20(_tokenAddress).balanceOf(address(this));
    }

    function getDepositDetails(uint256 _id) public view returns (address, address, uint256, uint256, bool) {
        return (
            lockedToken[_id].tokenAddress,
            lockedToken[_id].withdrawalAddress,
            lockedToken[_id].tokenAmount,
            lockedToken[_id].unlockTime,
            lockedToken[_id].withdrawn
        );
    }

    function getDepositsByWithdrawalAddress(address _withdrawalAddress) public view returns (uint256[] memory) {
        return depositsByWithdrawalAddress[_withdrawalAddress];
    }

    function getDepositsByTokenAddress(address _tokenAddress) public view returns (uint256[] memory) {
        return depositsByTokenAddress[_tokenAddress];
    }

    /* ─────────────────────INTERNAL FUNCTIONS───────────────────────────────────────*/

    /* ─────────────────────PRIVATE FUNCTIONS───────────────────────────────────────*/
}

