// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./IHWEscrow.sol";

contract HWRegistry is Ownable {
    struct Whitelist {
        address token;
        uint256 maxAllowed;
    }

    Counters.Counter public counter;
    IHWEscrow public hwEscrow;

    mapping(uint256 => Whitelist) public whitelist;
    mapping(uint256 => uint256) public nftGrossRevenue;

    event WhitelistAdded(address indexed _address, uint256 _maxAllowed);
    event WhitelistRemoved(address indexed _address);
    event WhitelistUpdated(address indexed _address, uint256 _maxAllowed);

    modifier onlyHWEscrow() {
        require(
            msg.sender == address(hwEscrow),
            "HWRegistry: Only HWEscrow can call this function"
        );
        _;
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function addToWhitelist(address _address, uint256 _maxAllowed)
        external
        onlyOwner
    {
        whitelist[Counters.current(counter)] = Whitelist({
            token: _address,
            maxAllowed: _maxAllowed
        });
        Counters.increment(counter);
        emit WhitelistAdded(_address, _maxAllowed);
    }

    function removeFromWhitelist(address _address) external onlyOwner {
        uint256 _id = getWhitelistID(_address);
        whitelist[_id] = Whitelist({token: address(0), maxAllowed: 0});
        emit WhitelistRemoved(_address);
    }

    function updateWhitelist(address _address, uint256 _maxAllowed)
        external
        onlyOwner
    {
        whitelist[getWhitelistID(_address)].maxAllowed = _maxAllowed;
        emit WhitelistUpdated(_address, _maxAllowed);
    }

    function setHWEscrow(address _address) external onlyOwner {
        hwEscrow = IHWEscrow(_address);
    }

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function setNFTGrossRevenue(uint256 _id, uint256 _amount)
        external
        onlyHWEscrow
    {
        nftGrossRevenue[_id] += _amount;
    }

    //----------------//
    //  view methods  //
    //----------------//

    function isWhitelisted(address _address) external view returns (bool) {
        bool isWhitelisted_;
        for (uint256 i = 0; i < Counters.current(counter); i++) {
            if (whitelist[i].token == _address) {
                isWhitelisted_ = true;
            }
        }
        return isWhitelisted_;
    }

    function getWhitelist() external view returns (Whitelist[] memory) {
        Whitelist[] memory whitelisted_ = new Whitelist[](
            Counters.current(counter)
        );
        for (uint256 i = 0; i < Counters.current(counter); i++) {
            whitelisted_[i] = whitelist[i];
        }
        return whitelisted_;
    }

    function getNFTGrossRevenue(uint256 _id) external view returns (uint256) {
        return nftGrossRevenue[_id];
    }

    function isAllowedAmount(address _address, uint256 _amount)
        public
        view
        returns (bool)
    {
        bool isAllowedAmount_;
        for (uint256 i = 0; i < Counters.current(counter); i++) {
            if (whitelist[i].token == _address) {
                if (whitelist[i].maxAllowed >= _amount) {
                    isAllowedAmount_ = true;
                }
            }
        }
        return isAllowedAmount_;
    }

    function getWhitelistID(address _address) internal view returns (uint256) {
        uint256 token_id;
        for (uint256 i = 0; i < Counters.current(counter); i++) {
            if (whitelist[i].token == _address) {
                token_id = i;
            }
        }
        return token_id;
    }
}

