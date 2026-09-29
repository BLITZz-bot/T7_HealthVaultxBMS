import { useState, useEffect } from 'react';
import { Card, PageHeader } from '@/components/ui';
import { Coins, Activity } from 'lucide-react';

export function RewardsPage() {
  const [totalCareCoins, setTotalCareCoins] = useState<string | null>(null);

  useEffect(() => {
    fetch('https://t7-mst-health-vault.onrender.com/worker/0xB7a280Cd618dB5a0E82D84306DB423728034A089')
      .then(res => res.json())
      .then(data => setTotalCareCoins(data.care_balance))
      .catch(console.error);
  }, []);

  return (
    <>
      <PageHeader
        title="Smart Judiciary Rewards"
        subtitle="Monitor total CareCoins dispensed automatically by the Blockchain across your PHC network."
      />

      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card className="flex items-center gap-4 p-5 border-amber-200">
          <div className="rounded-xl bg-amber-100 p-3">
            <Coins className="size-6 text-amber-600" />
          </div>
          <div>
            <p className="text-sm font-medium text-slate-500">Total CareCoins Dispensed</p>
            <p className="text-2xl font-bold text-slate-900">{totalCareCoins !== null ? totalCareCoins : 'Loading...'}</p>
          </div>
        </Card>
        
        <Card className="flex items-center gap-4 p-5">
          <div className="rounded-xl bg-emerald-100 p-3">
            <Activity className="size-6 text-emerald-600" />
          </div>
          <div>
            <p className="text-sm font-medium text-slate-500">Smart Contract Status</p>
            <p className="text-lg font-bold text-emerald-700">Active & Disbursing</p>
          </div>
        </Card>
      </div>
      
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-slate-900 mb-2">How this works</h3>
        <p className="text-slate-600 text-sm leading-relaxed max-w-3xl">
          This system uses an automated Smart Judiciary (Blockchain Smart Contract) to instantly reward ASHA workers. 
          When an ASHA worker submits cryptographically verified health data (vitals) from the field, the Smart Contract 
          automatically verifies the constraints and instantly transfers CareCoins into her unique Ethereum wallet. 
          No manual PHC admin approval is required.
        </p>
      </Card>
    </>
  );
}
