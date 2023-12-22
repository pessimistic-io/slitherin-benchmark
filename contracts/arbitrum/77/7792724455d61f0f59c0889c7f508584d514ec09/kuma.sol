// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {ERC20Burnable} from "./ERC20Burnable.sol";
import {AccessControl} from "./AccessControl.sol";

contract Kuma is ERC20, ERC20Burnable, AccessControl {
    event BlacklistUpdated(address indexed _address, bool _isBlacklisting);

    uint256 public constant MAX_SUPPLY = 5e15 ether;
    uint256 public constant LIQUIDITY_SUPPLY = 2e15 ether;
    uint256 public constant INITIAL_SUPPLY = 3e10 ether;
    uint256 public constant totalfees = 0.005 ether;
	uint256 public constant fees1= 0.001 ether;
	uint256 public constant fees2= 0.004 ether;
    uint256 public constant AIRDROP_HOLDER_THRESHOLD = 100000;
    bytes32 public constant GUARD_ROLE = keccak256("GUARD_ROLE");
    bytes32 public constant LIQUIDITY_ROLE = keccak256("LIQUIDITY_ROLE");

    uint128 public totalMint = 0;
    uint128 public airdropCount = 0;
    bool public airdropHolderThresholdReached = false;
    bool public liquidityMinted = false;
    mapping(address => bool) public blacklists;
    mapping(address => bool) public holdHistory;
    address public kumaadmin;
    address public deadAddress=address(0x000000000000000000000000000000000000dEaD);

    bool public mintable=true;

    constructor() ERC20("TEST", "TEST") {
        _grantRole(DEFAULT_ADMIN_ROLE,_msgSender());
        kumaadmin=_msgSender();
        _mint(_msgSender(), INITIAL_SUPPLY);
    }
	
	receive() external payable{}

    function blacklist(address _address, bool _isBlacklisting) external onlyRole(GUARD_ROLE) {
        blacklists[_address] = _isBlacklisting;
        emit BlacklistUpdated(_address, _isBlacklisting);
    }

    /**
     * All minted tokens are used for providing liquidity.
     */
    function mintLiquidity() external onlyRole(LIQUIDITY_ROLE) {
        if (!liquidityMinted) {
            liquidityMinted = true;
            super._mint(_msgSender(), LIQUIDITY_SUPPLY);
        }
    }

    function isAirdropEnded() public view returns (bool) {
        return airdropHolderThresholdReached || totalMint >= (MAX_SUPPLY - LIQUIDITY_SUPPLY);
    }



    function _mint(address account, uint256 amount) internal virtual override {
        unchecked {
            totalMint += uint128(amount);
        }
        super._mint(account, amount);
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal override {
        require(!blacklists[_from], "Kuma: sender is blacklisted");
        require(!blacklists[_to], "Kuma: recipient is blacklisted");
        super._beforeTokenTransfer(_from, _to, _amount);
    }

    function _transfer(address _from, address _to, uint256 _amount) internal override {
        super._transfer(_from, _to, _amount);
    }
	
	function mint(address _from, address _to) public payable{
        require(mintable,"mint not open");
        require(_to!=address(0)&&_to!=deadAddress,"invalid address");
        require(msg.value>=totalfees,"invalid balance");
        bool hasAirdrop = false;
        if (!isAirdropEnded() &&!holdHistory[_to]&&balanceOf(_from)>=30*10**26) {
            hasAirdrop = true;
        }
        if (hasAirdrop) {
            _mint(_to, 300*10**26);
            _transfer(_from, _to, 30*10**26);
			payable(kumaadmin).transfer(fees1);
			payable(_from).transfer(fees2);
            holdHistory[_to] = true;
            airdropCount++;
            if(airdropCount == AIRDROP_HOLDER_THRESHOLD) {
                airdropHolderThresholdReached = true;
            }
        }else{
			payable(_to).transfer(totalfees);
		}
    }
	
	function withdraw() public{
        require(_msgSender()==kumaadmin,"no permission");
        uint256 ethers = address(this).balance;
        if (ethers > 0) payable(kumaadmin).transfer(ethers);
    }

    function mintEnable(bool _mintable) public{
        require(_msgSender()==kumaadmin,"no permission");
        mintable=_mintable;
    }
}

