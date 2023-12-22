// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Strings.sol";
import "./Base64.sol";
import "./ITreasury.sol";
import "./IItem.sol";
import "./IWETH.sol";
import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";


contract Item is IItem, ERC1155Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;
    using Base64 for bytes;

    event Buy(address indexed account, uint256 indexed itemId, uint256 amount);

    string public name;
    string public symbol;
    uint256 public minted;
    mapping (uint256 => uint256) public tokenSupply;

    ITreasury public treasury;
    mapping (uint256 => ItemConfig) public configs;
    mapping(address => bool) public authControllers;

    function initialize(
        address _treasury
    ) external initializer {
        require(_treasury != address(0));
        __ERC1155_init("");
        __Ownable_init();
        __Pausable_init();
        treasury = ITreasury(_treasury);
        name = "EnergyCrisis Item";
        symbol = "ECI";
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setConfigs(ItemConfig[] memory _configs) external onlyOwner {
        for (uint256 i = 0; i < _configs.length; ++i) {
            configs[_configs[i].itemId] = _configs[i];
        }
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    receive() external payable {}

    function buy(uint256 _itemId, uint256 _amount, uint8 _payToken) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        ItemConfig memory config = configs[_itemId];
        require(_itemId == config.itemId, "Item does not exist");
        require(config.price > 0, "Not sale");

        uint256 price = _amount.mul(config.price);
        (address token, uint256 amount) = treasury.getAmount(_payToken, price);
        if (treasury.isNativeToken(token)) {
            require(amount == msg.value, "amount != msg.value");
            IWETH(token).deposit{value: msg.value}();
            IERC20(token).safeTransfer(address(treasury), amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(treasury), amount);
        }

        minted = minted.add(_amount);
        tokenSupply[_itemId] = tokenSupply[_itemId].add(_amount);
        _mint(_msgSender(), _itemId, _amount, "");
        emit Buy(_msgSender(), _itemId, _amount);
    } 

    function burn(address _account, uint256 _itemId, uint256 _amount) public override {
        require(
            authControllers[_msgSender()] == true ||
            _account == _msgSender() || isApprovedForAll(_account, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _burn(_account, _itemId, _amount);
    }

    function uri(uint256 _itemId) public view override returns (string memory) {
        ItemConfig memory config = configs[_itemId];
        string memory imageUrl = nftUrl(config.itemId);
        string memory metadata = string(abi.encodePacked(
        '{"name": "',
        config.name,
        ' #',
        _itemId.toString(),
        '", "description": "", ',
        imageUrl,
        ', "attributes":',
        compileAttributes(config),
        "}"
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            base64(bytes(metadata))
        ));
    }

    function attributeForTypeAndValue(string memory traitType, string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            traitType,
            '","value":"',
            value,
            '"}'
        ));
    }

    function compileAttributes(ItemConfig memory _config) public pure returns (string memory) {
        string memory traits = string(abi.encodePacked(
            attributeForTypeAndValue("Type", uint256(_config.itemType).toString()),',',
            attributeForTypeAndValue("Value", uint256(_config.value).toString()), ',',
            attributeForTypeAndValue("Description", _config.des)
        ));
    
        return string(abi.encodePacked(
            '[',
            traits,
            ']'
        ));
    }

    function nftUrl(uint256 _itemId) public pure returns(string memory) {
        string memory ipfsHash = "QmU4UNjm1tjGvmhjMQjaZMEnDpDJRwLAabeD8odMm4Vn2g";
        return string(abi.encodePacked('"image": "https://energycrisis.mypinata.cloud/ipfs/',
            ipfsHash,
            '/',
            _itemId.toString(),
            '.png"'
        ));
    }

    /** BASE 64 - Written by Brech Devos */
    string public constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return '';
    
        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)
      
            // prepare the lookup table
            let tablePtr := add(table, 1)
      
            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
      
            // result ptr, jump over length
            let resultPtr := add(result, 32)
      
            // run over the input, 3 bytes at a time
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
          
                // read 3 bytes
                let input := mload(dataPtr)
          
                // write 4 characters
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr( 6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(        input,  0x3F)))))
                resultPtr := add(resultPtr, 1)
            }
      
            // padding with '='
            switch mod(mload(data), 3)
                case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
                case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
        }
    
        return result;
    }

    function balanceOfBatch(address _account, uint32[] memory _itemIds)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory batchBalances = new uint256[](_itemIds.length);
        for (uint256 i = 0; i < _itemIds.length; ++i) {
            batchBalances[i] = balanceOf(_account, _itemIds[i]);
        }
        return batchBalances;
    }

    function getConfig(uint256 _itemId) external view override returns(ItemConfig memory) {
        return configs[_itemId];
    }
}
