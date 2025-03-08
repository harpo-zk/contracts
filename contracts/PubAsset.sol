//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

contract PubAsset {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) internal _balances;
       
    constructor() {
        symbol = "DRX";
        name = "DREX";
        decimals = 2;
        totalSupply = 5000000000000000000000000000;
        _balances[msg.sender] = totalSupply;
    }
    
    function transfer(
        address _to,
        uint256 _value
    ) external returns (bool) {
        require(_to != address(0), "ERC20: to address is not valid");
        require(_value <= _balances[msg.sender], "ERC20: insufficient balance");

        _balances[msg.sender] = _balances[msg.sender] - _value;
        _balances[_to] = _balances[_to] + _value;
       
        return true;
    }
    
    function balanceOf(
        address _owner
    ) external view returns (uint256 balance) {
        return _balances[_owner];
    }
    
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool) {
        require(_from != address(0), "ERC20: from address is not valid");
        require(_to != address(0), "ERC20: to address is not valid");
        require(_value <= _balances[_from], "ERC20: insufficient balance");      

        _balances[_from] = _balances[_from] - _value;
        _balances[_to] = _balances[_to] + _value;
        
        return true;
    }
    
    function mintTo(address _to, uint256 _amount) external returns (bool) {
        require(_to != address(0), "ERC20: to address is not valid");

        _balances[_to] = _balances[_to] + _amount;
        totalSupply = totalSupply + _amount;       

        return true;
    }
    
    function burn(uint256 _amount) external returns (bool) {
        require(
            _balances[msg.sender] >= _amount,
            "ERC20: insufficient balance"
        );

        _balances[msg.sender] = _balances[msg.sender] - _amount;
        totalSupply = totalSupply - _amount;      

        return true;
    }
    
    function burnFrom(address _from, uint256 _amount) external returns (bool) {
        require(_from != address(0), "ERC20: from address is not valid");
        require(_balances[_from] >= _amount, "ERC20: insufficient balance");
        
        _balances[_from] = _balances[_from] - _amount;
        totalSupply = totalSupply - _amount;
      

        return true;
    }
   
    function approve(
        address _spender,
        uint256 _value
    ) external returns (bool success) {}

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256 remaining) {}
}