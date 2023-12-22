// SPDX-License-Identifier: MIT

/*
    twitter: https://twitter.com/arbmaku
*/
pragma solidity ^0.8.10;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./Address.sol";

contract MAKU is ERC20, ERC20Burnable, Ownable {
    using Address for address;
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000 ether;
    uint256 public constant AIRDROP_SUPPLY = 400_000_000_000 ether;
    uint256 public constant AIRDROP_AMOUNT = 60_000_000 ether;
    uint256 public constant AIRDROP_THRESHOLD = 10_000_000 ether;

    mapping(address => bool) public HOLDERS;

    mapping(address => uint256) public INVITE_COUNTS;

    mapping(address => bool) public CAN_CLAIMS;

    mapping(address => address) public REFERRERS;

    uint256 public START_TIME = 1689166800;

    address public FEE_ADDRESS;

    bool public PAUSED = false;

    constructor() ERC20("ARB MAKU", "MAKU") {
        FEE_ADDRESS = msg.sender;
        _mint(msg.sender, MAX_SUPPLY - AIRDROP_SUPPLY);
    }

    event Invite(address indexed inviter, address indexed invitee, uint256 count);

    function flipPause() external onlyOwner {
        PAUSED = !PAUSED;
    }

    function _getAirdropAmount() public view returns (uint256) {
        if (block.timestamp < START_TIME) {
            return AIRDROP_AMOUNT;
        }
        uint256 duration = block.timestamp - START_TIME;
        uint256 durationAmount = duration * 1_000 * 1e18;
        if (durationAmount > 30_000_000 ether) {
            return 30_000_000 ether;
        }
        return AIRDROP_AMOUNT - durationAmount;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20) {
        if (PAUSED) {
            return;
        }

        if (from == address(0) || to == address(0)) {
            return;
        }

        if (from == owner()) {
            return;
        }

        if (from == to) {
            return;
        }

        if (from.isContract() || to.isContract()) {
            return;
        }

        if (amount < AIRDROP_THRESHOLD) {
            return;
        }

        if (INVITE_COUNTS[from] >= 30) {
            return;
        }

        // old holder, return
        if (HOLDERS[to]) {
            return;
        }

        HOLDERS[to] = true;
        REFERRERS[to] = from;
        CAN_CLAIMS[to] = true;
        INVITE_COUNTS[from] += 1;
        emit Invite(from, to, INVITE_COUNTS[from]);
    }

    receive() payable external {
        require(msg.sender == tx.origin, "eoa");
        require(msg.value >= 0.002 ether);
        require(CAN_CLAIMS[msg.sender], "can not claim");
        CAN_CLAIMS[msg.sender] = false;

        uint256 airdropAmount = _getAirdropAmount();
        if (airdropAmount + totalSupply() <= MAX_SUPPLY) {
            _mint(msg.sender, airdropAmount);
        }

        if (REFERRERS[msg.sender] != address(0)) {
            if (airdropAmount + totalSupply() <= MAX_SUPPLY) {
                _mint(REFERRERS[msg.sender], airdropAmount);
            }
        }

        payable(FEE_ADDRESS).transfer(msg.value);
    }
}

