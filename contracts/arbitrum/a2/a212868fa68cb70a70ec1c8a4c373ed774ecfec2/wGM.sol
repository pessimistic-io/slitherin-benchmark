// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";

import "./Utils.sol";

/**
 * Implements Wrapped GM as ERC20 token.
 *
 * The local GM pool size will always match the total supply of wGM tokens
 * since they are minted on deposit and burned on withdraw in 1:1 ratio.
 */

interface IFREN {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IGM {
    function balanceOf(address, uint256) external view returns (uint256);
}

contract wTest is ERC20, Ownable, ReentrancyGuard {
    //wGM token
    address public NFA_ERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public GM_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public GM_ERC1155 = 0x5A8b648dcc56e0eF241f0a39f56cFdD3fa36AfD5;
    address public GM_ERC721 = 0x000000000000000000000000000000000000dEaD;
    uint256 public ID = 3;
    GM frensGM;
    mapping(address => uint256) public unWrapTimeStamp;
    mapping(address => bool) private _isFrenChef;

    uint256 unWrapInterval = 1 minutes;
    uint256 unWrapEpoch = 3 minutes;
    uint256 multiplier = 1;
    uint256 divisor = 100;
    uint256 gm_mul = 5;
    uint256 gm_div = 4;
    uint256 deployTimestamp;

    bool public openGM = false;
    // Error Code: No error.
    uint256 public constant ERR_NO_ERROR = 0x0;

    // Error Code: Non-zero value expected to perform the function.
    uint256 public constant ERR_INVALID_ZERO_VALUE = 0x01;

    // create instance of the wGM token
    constructor() public ERC20("TestLel", "KEKUS") {
        frensGM = GM(NFA_ERC721);
        deployTimestamp = block.timestamp;
    }

    //  wraps received GM tokens as wGM in 1:1 ratio by minting
    // the received amount of GMs in wGM on the sender's address.
    function wrap(uint256 _amount) public returns (uint256) {
        require(IFREN(GM_ERC20).balanceOf(msg.sender) >= _amount, "Fren GM amount insuficient");
        unWrapTimeStamp[msg.sender] = block.timestamp;
        // there has to be some value to be converted
        if (_amount == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }
        IFREN(GM_ERC20).transferFrom(msg.sender, address(this), _amount);
        // we already received GMs, mint the appropriate amount of wGM
        _mint(msg.sender, _amount);

        // all went well here
        return ERR_NO_ERROR;
    }

    //  unwraps GM tokens by burning specified amount
    // of wGM from the caller address and sending the same amount
    // of GMs back in exchange.
    function unwrap(uint256 amount) public returns (uint256) {
        require(IFREN(address(this)).balanceOf(msg.sender) >= amount, "Fren wGM amount insuficient");
        require(IFREN(GM_ERC20).balanceOf(address(this)) >= amount, "Contract GM amount insuficient");

        // there has to be some value to be converted
        if (amount == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }

        if (openGM || msg.sender == owner() || IFREN(GM_ERC721).balanceOf(msg.sender) > 0) {
            // burn wGM from the sender first to prevent re-entrance issue
            _burn(msg.sender, amount);

            // if wGM were burned, transfer native tokens back to the sender
            IFREN(GM_ERC20).transfer(msg.sender, amount);
            // all went well here
            return ERR_NO_ERROR;
        } else {
            require(block.timestamp > unWrapTimeStamp[msg.sender] + unWrapInterval, "Fren must wait to unwrap again");
            uint256 unWrapamount = unWrapAmount(msg.sender);

            require(amount <= unWrapamount, "Your wGM amount exceeds your unwrap limit");

            _burn(msg.sender, amount);

            // if wGM were burned, transfer native tokens back to the sender
            IFREN(GM_ERC20).transfer(msg.sender, amount);
        }
        unWrapTimeStamp[msg.sender] = block.timestamp;
        return amount;
    }

    function frenGM(address fren) public view returns (uint256) {
        return frensGM.user_GM(fren);
    }

    function unWrapAmount(address fren) public view returns (uint256) {
        uint256 gmAmount = frenGM(fren);
        uint256 wGMBalance = balanceOf(fren);
        uint256 GMERC1155 = IGM(GM_ERC1155).balanceOf(msg.sender, ID);
        uint256 max_unwrapAmount = (wGMBalance * gmAmount * multiplier) / divisor;
        uint256 timelapsed;

        if (GMERC1155 > 0) {
            timelapsed = block.timestamp - (unWrapTimeStamp[fren] * GMERC1155 * gm_mul) / gm_div;
        } else {
            timelapsed = block.timestamp - unWrapTimeStamp[fren];
        }

        if (timelapsed > unWrapEpoch || unWrapTimeStamp[fren] == 0) {
            return max_unwrapAmount;
        } else {
            uint256 unwrapAmount = (max_unwrapAmount * timelapsed) / unWrapEpoch;
            return unwrapAmount;
        }
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        unWrapTimeStamp[to] = block.timestamp;

        super._transfer(from, to, amount);
    }

    function widthrawGM(address token) external onlyOwner {
        uint256 balance = IFREN(token).balanceOf(address(this));
        IFREN(token).transfer(msg.sender, balance);
    }

    function setOpenWrap(bool _bool) external onlyOwner {
        openGM = _bool;
    }

    function changeGM(address _GM_ERC20) external onlyOwner {
        GM_ERC20 = _GM_ERC20;
    }

    function changeGMCounter(address _gm) external onlyOwner {
        frensGM = GM(_gm);
    }

    function changeGMNFT(address _gm, uint256 _id, address _GM_ERC721) external onlyOwner {
        GM_ERC721 = _GM_ERC721;
        GM_ERC1155 = _gm;
        ID = _id;
    }

    function changeTime(uint256 _unWrapInterval, uint256 _unWrapEpoch) external onlyOwner {
        unWrapInterval = _unWrapInterval;
        unWrapEpoch = _unWrapEpoch;
    }

    function changeConstants(
        uint256 _multiplier,
        uint256 _divisor,
        uint256 _gm_mul,
        uint256 _gm_div
    ) external onlyOwner {
        multiplier = _multiplier;
        divisor = _divisor;
        gm_mul = _gm_mul;
        gm_div = _gm_div;
    }

    function mint(address fren, uint256 amount) public onlyFrenChef {
        _mint(fren, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function setFrenChef(address[] calldata _addresses, bool chef) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isFrenChef[_addresses[i]] = chef;
        }
    }

    modifier onlyFrenChef() {
        require(_isFrenChef[msg.sender], "You are not FrenChef");
        _;
    }
}

