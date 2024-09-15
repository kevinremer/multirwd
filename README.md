# Overview

These contracts are meant to serve as a generic structure for a token that offers multiple rewards via a single reward distributor. They should deploy successfully on most EVM compatible chains (ETH, BSC, etc.)  

If you wish to hire me to assist in deployement, launching or modifications, please reach out to me at https://x.com/kevinremer  

# Token

## Description

This contract creates a pausable token with adjustable taxes, and will swap taxes back for WETH using a dynamic swap thredhold that is based on average transaction size.  

It allows for the following exemptions:  
Fee exempt - Does not pay taxes on buys and sells  
Freeze exempt - Can move tokens while contract is frozen  
Process exempt - Will not process rewards on transactions  
Reward exempt - Does not receive rewards  

## Deployment

Deploying this contract requires the following variables sent to the constructor:  
router_ - Address of the router you plan to use for swapping tokens for WETH, and for creating the initial LP Pair upon deployment  
defaultReceiver_ - The address you want WETH sent to after swapbacks occur. This is also the default receiver for reward WETH (must be changed later)  
totalSupply_ - THe value expressed as a real number (will be converted to wei in the constructor)  

# Distributor

## Description

-Uses 2 arrays, buyRewards and sendRewards  
-When you add a token it gets added to both arrays  
-You can add ERC20 tokens or use native WETH (not wrapped)  
-You can remove a token from buyRewards and it will distribute until totalDistributed = totalDividends, then remove it from sendRewards  
-It will accept WETH from any source  
-When WETH hits the threshold, it splits the WETH equally among the tokens in buyRewards  
-Process() will either buy/allocate more rewards or distribute anything in sendRewards  
-You can also reactivate a deactivated token into buyRewards as long as it is still in sendRewards  

## Deployment

Deploying this contract requires the following variables sent to the constructor:  
parentToken_ - Address of the token deployed by the token contract above  
rewardRouter_ - Address of the router you plan to use for swapping WETH for reward tokens  

# Additional configuration

Once both contracts are depoloyed, you must call the following function on the deployed token contract:  
setDistributor(address rwdDistributor_)  

Simply call that function and pass the address of the newly deployed Distributor  

# License

MIT License  

Copyright (c) 2024 Kevin Remer (Totenmacher)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.