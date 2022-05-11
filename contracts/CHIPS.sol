// contracts/CHIPS.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";


contract CHIPS is Initializable, ERC20Upgradeable, OwnableUpgradeable{
    using SafeMathUpgradeable for uint256;
    IERC20Upgradeable private token;
    
    address public uniswapV2Pair;
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Factory public uniswapFactory;
    
    address internal constant UNISWAP_ROUTER_ADDRESS   = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_FACTORY_ADDRESS  = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    
    bool public isDistributed;
    uint256 private constant TOTAL_SUPPLY =  100000000;//  100000000 * 10 ** decimals() // 100 million

    // distribution/ miniting addresses
    address public teamAddress;
    address public treasuryAddress;
    address public stakeRewardAddress;

    // Tax Fee 
    uint256 private constant buyTax  = 2;
    uint256 private constant sellTax = 8;

    // Tax Fee Percentages to redistribute 
    uint256 private constant liquidityPercentage = 35;
    uint256 private constant treasuryPercentage  = 25;
    uint256 private constant stakingRewardPercentage = 40;

    // collet liquidity amount
    uint256 private lpLimit;
 
    event CurrentBalane(uint curBal);

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "CHIPS :: Cannot be called by a contract");
        _;
    }


    function initialize() external initializer{
        __ERC20_init("CHIPS", "$CHIPS");
        __Ownable_init();
        lpLimit              = 100000000000000000000;  // 100 tokens
        token                = IERC20Upgradeable(address(this));

        // BEGIN::Remove in production
        // set variables
            teamAddress          = 0x7023A483443785B7A06ae15D0f6544a22E09d374;
            treasuryAddress      = 0x213252E60A29d0f35D9CD31E10B6DAEC826010f0;
            stakeRewardAddress   = 0x56A751409eFf7fC24E240f8031c1f0CdFAf76978;
        // END::Remove in production

        uniswapRouter        = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        uniswapFactory       = IUniswapV2Factory(UNISWAP_FACTORY_ADDRESS);
    }

    function distribute() external payable onlyOwner{

        // validate addresses
        require(!(isDistributed), "CHIPS :: Already distributed");
        require(teamAddress != address(0), "CHIPS: cannot mint to the zero team address");
        require(treasuryAddress != address(0), "CHIPS: cannot mint to the zero treasury address");
        require(stakeRewardAddress != address(0), "CHIPS: cannot mint to the zero stakeReward address");

        // distribute the tokens
        _mint(address(this), (TOTAL_SUPPLY.mul(15).div(1000)) * 10 ** decimals());             // Initial Liquidity => 1.5%
        _mint(teamAddress, (TOTAL_SUPPLY.mul(100).div(1000)) * 10 ** decimals());           // Team => 10%
        _mint(treasuryAddress, (TOTAL_SUPPLY.mul(205).div(1000)) * 10 ** decimals() );      // Treasury => 20.5%
        _mint(stakeRewardAddress, (TOTAL_SUPPLY.mul(680).div(1000)) * 10 ** decimals());    // Staking Pool Rewards  => 68%
        
        // create pair 
        uniswapV2Pair       = uniswapFactory.createPair(address(this), uniswapRouter.WETH());

        // provide initial liquidity
        addLiquidity();

        // toggle distribution
        toggleDistribute();
    }

    function toggleDistribute() internal{
        isDistributed = !isDistributed;
    }

    
    function provideLiquidity() external payable onlyOwner{
        require((isDistributed), "CHIPS :: not distributed yet");
        addLiquidity();
    }


    function addLiquidity() internal returns(bool){
        emit CurrentBalane(address(this).balance);
        uint256 tokenAmount = token.balanceOf(address(this)); // CHIPS balance in this contract
        uint256 etherAmount = address(this).balance;   // ether balance in this contract
        require(tokenAmount > lpLimit, "CHIPS: More chips required");
        require(etherAmount > 0, "CHIPS: More Ether required");
        
        
        IERC20Upgradeable(token).approve(UNISWAP_ROUTER_ADDRESS, tokenAmount);
        require(token.allowance(address(this), UNISWAP_ROUTER_ADDRESS) != 0,"zero allowance, pleae approve CHIPS first to be used by this contract");
        uniswapRouter.addLiquidityETH{value: etherAmount}(
            address(token),
            tokenAmount,//tkn amount
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        // refund leftover ETH to user
        (bool success,) = address(this).call{ value: address(this).balance }("");
        require(success, "refund failed");
    }

    //to check balance of receiveAbleTokens 
    function checkReceivedTokensBalance() external view onlyOwner returns(uint balance){
        return token.balanceOf(address(this));
    }

    //transfer tokens to msg.sender
    function transferToken() external onlyOwner {
        uint tokenAmount = token.balanceOf(address(this));
        require(token.transferFrom(address(this), msg.sender, tokenAmount) == true,"transferToken: Error in CHIPS transfer");
    }
  
    //get totalBalance of contract in ether
    function totalBalance() external onlyOwner view returns(uint) {
        return address(this).balance;
    }

    //function to withdrawFunds from contract
    function withdrawFunds() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function _transfer(address from,address to,uint256 amount)internal override{
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(tx.origin  == owner()){
            super._transfer(from, to, amount);
        }else{
            uint taxAmount;
            if(to == address(uniswapV2Pair) ) {
                taxAmount  = amount.mul(8).div(100);
            } else if (from == address(uniswapV2Pair)){
                taxAmount  = amount.mul(2).div(100);
            }
            amount          = amount - taxAmount; 
            super._transfer(from, address(this), taxAmount); // get tax collected 
            super._transfer(from, to, amount);
            distributeTaxAmount(taxAmount);
        }
    }

    function distributeTaxAmount(uint256 amount) internal {
        require(treasuryAddress != address(0), "CHIPS: cannot mint to the zero treasury address");
        require(stakeRewardAddress != address(0), "CHIPS: cannot mint to the zero stakeReward address");
       
        // super._transfer(address(this), address(this), amount.mul(liquidityPercentage).div(100));
        super._transfer(address(this), treasuryAddress, amount.mul(treasuryPercentage).div(100)); 
        super._transfer(address(this), stakeRewardAddress, amount.mul(stakingRewardPercentage).div(100));
    }
    
    function buyBack(uint256 amount) public onlyOwner {
        require(balanceOf(msg.sender) >= amount, "You have insufficient CHIPS");
        transfer(treasuryAddress, (amount.mul(400).div(1000)) );  // 40% Treasury 
        transfer(stakeRewardAddress, (amount.mul(300).div(1000)) ); // 30% Staking Rewards Pool
        _burn(msg.sender, (amount.mul(300).div(1000)) );  // 30% Token Burning
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function setLpLimit(uint256 limit) external onlyOwner{
        lpLimit = limit;
    }
    
    function getLpLimit() public view returns(uint256){
        return lpLimit;
    }

    function setTeamAddress(address _teamAddress) external onlyOwner{
        teamAddress = _teamAddress;
    }
    
    function getTeamAddress() public view returns(address){
        return teamAddress;
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner{
        treasuryAddress = _treasuryAddress;
    }

    function getTreasuryAddress() public view returns(address){
        return treasuryAddress;
    }

    function setStakeRewardAddress(address _stakeRewardAddress) external onlyOwner{
        stakeRewardAddress = _stakeRewardAddress;
    }

    function getStakeRewardAddress() public view returns(address){
        return stakeRewardAddress;
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    // important to receive ETH
    receive() payable external {}

}
