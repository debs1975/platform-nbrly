
# I prefer more replicas as per the need rather than allocating higher capacity upfront. Optimize the analysis for Azure Container apps only, however give a comparision with AKS and App Service

## Azure Container Apps - Optimized for Your Requirements

### **Why Azure Container Apps Wins for 50-60 RPS Per Container**

**Key Advantages:**

**1. True Horizontal Scaling with KEDA**

- Autoscaling based on HTTP concurrency (per 15-second window)
- Scale metric: When concurrent requests exceed your threshold (55), new replicas auto-create
- Scaling happens in 3-5 seconds (fastest of all three options)
- No manual intervention needed

**2. Scale-to-Zero (Cost Optimizer)**

- Replicas scale down to 0 when idle
- Containers at rest: Nearly \$0/month
- Perfect for dev/test or bursty traffic
- Only Container Apps offers true scale-to-zero (AKS must keep control plane running, App Service can't scale to zero)

**3. Per-Second Billing (Pay Only for Usage)**

- First 180,000 vCPU-seconds free/month
- First 360,000 GiB-seconds free/month
- Beyond that: ~\$0.018 per vCPU-second, \$0.0036 per GiB-second
- For continuous 2-replica baseline at 0.5 vCPU + 1 GB: ~\$20-30/month

**4. Minimal Operational Overhead**

- No cluster to manage, no node patching
- No Kubernetes expertise required
- Azure handles all infrastructure updates
- Focus only on application code


### **Scaling Tiers for Your Architecture**

| Load (RPS) | Replicas | Monthly Cost | Best For |
| :-- | :-- | :-- | :-- |
| 0-55 | 1-2 | \$10-20 | Dev, testing, low traffic |
| 55-110 | 2 | \$20-30 | Production baseline (HA) |
| 110-165 | 3 | \$30-45 | Growing traffic |
| 165-275 | 5 | \$50-75 | Medium production |
| 275-550 | 10 | \$100-150 | High traffic |
| 550-1100 | 20 | \$200-300 | Enterprise scale |

### **HTTP Concurrency Scaling Configuration**

```bash
az containerapp create \
  --name fastapi-app \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 2 \
  --max-replicas 30 \
  --scale-rule-type http \
  --scale-rule-http-concurrency 55
```

This automatically:

- Keeps minimum 2 replicas running (production HA)
- Adds a replica when concurrent requests exceed 55 per replica
- Removes replicas when load drops (conservative 5-minute delay)
- Maximum of 30 replicas (cost safety limit)

***

## Comparison with Alternatives

### **AKS (Azure Kubernetes Service)**

**When to consider AKS:**

- Need full Kubernetes control and APIs
- Running stateful services (databases, caches with persistent volumes)
- Require service meshes (Istio, Linkerd)
- Complex networking requirements

**Cost for same workload:**

- Control plane: \$72/month (always running)
- 3-4 nodes for 550 RPS: ~\$300/month
- **Total: ~\$372+/month** (3.7x more expensive than Container Apps)

**Scaling speed:** 10-30 seconds (slower)

**Operational burden:** High (manage cluster upgrades, node pools, security patches)

**Verdict:** Overkill for simple FastAPI APIs unless you need Kubernetes-specific features

### **App Service**

**When to consider App Service:**

- Traditional web applications
- .NET or Windows container workloads
- Need Windows support
- Predictable steady-state traffic

**Cost for same workload:**

- B2 Plan (1 vCPU, 3.5 GB) × 10 instances = ~\$750/month
- **Cannot scale to zero** (always paying)

**Scaling speed:** 1-2 minutes (much slower)

**Maximum replicas:** Limited to ~30-40 per plan

**Scaling model:** HTTP traffic only, less flexible

**Verdict:** Higher cost, slower scaling, no scale-to-zero; only choose if you need Windows containers or prefer traditional PaaS simplicity

***

## Cost Analysis: Real Numbers

**Baseline (2 replicas × 0.5 vCPU + 1 GB):**

- Container Apps: ~\$20-30/month
- AKS: ~\$107/month minimum
- App Service: ~\$150/month (2 B2 instances)

**At 550 RPS (10 replicas):**

- Container Apps: ~\$100-120/month
- AKS: ~\$372/month
- App Service: ~\$750/month

**Savings with Container Apps:**

- 74% cheaper than AKS
- 87% cheaper than App Service

***

## Final Recommendation

**🎯 Start with Azure Container Apps**

Because:

1. **Perfect fit:** Built for 50-60 RPS per container with horizontal scaling
2. **Cost-efficient:** 70-87% cheaper than alternatives
3. **Automatic:** KEDA-based autoscaling requires no manual work
4. **Fast scaling:** 3-5 seconds vs 10-30s (AKS) or 1-2min (App Service)
5. **Cloud-native:** Aligns with your platform engineering approach
6. **Future-proof:** Easy to migrate to AKS if you need Kubernetes later

**Configuration:**

- Start with 2 replicas (HA baseline)
- 0.5 vCPU + 1 GB per replica (Azure's constraint)
- HTTP concurrency scale rule at 55 requests/replica
- Max 30 replicas (adjust based on growth)
- Monitor for 2 weeks, then tune

This approach gives you exactly what you asked for: replicas that scale automatically as needed, without allocating excess capacity upfront.
<span style="display:none">[^1][^10][^11][^12][^13][^14][^15][^16][^17][^18][^2][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://azurefeeds.com/2025/10/04/choosing-the-right-azure-containerisation-strategy-aks-app-service-or-container-apps/

[^2]: https://learn.microsoft.com/en-us/azure/container-apps/scale-app

[^3]: https://turbo360.com/blog/azure-horizontal-vs-vertical-scaling

[^4]: https://techcommunity.microsoft.com/blog/appsonazureblog/choosing-the-right-azure-containerisation-strategy-aks-app-service-or-container-/4456645

[^5]: https://paulyu.dev/article/azure-container-apps-autoscaling/

[^6]: https://codeteddy.com/2023/08/01/horizontal-scaling-and-vertical-scaling-in-azure/

[^7]: https://www.einfochips.com/blog/choosing-the-best-azure-service-for-your-application-app-services-vs-aci-vs-container-apps-vs-aks/

[^8]: https://blog.nashtechglobal.com/autoscaling-in-azure-container-apps/

[^9]: https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale

[^10]: https://www.site24x7.com/learn/azure-aca-vs-aks.html

[^11]: https://dev.to/alexortigosa/from-app-service-plans-to-azure-container-apps-reducing-costs-by-99-1lbg

[^12]: https://learn.microsoft.com/en-us/azure/app-service/manage-automatic-scaling

[^13]: https://developersvoice.com/blog/cloud/azure-app-service-aks-container-apps-benchmark/

[^14]: https://github.com/microsoft/azure-container-apps/issues/554

[^15]: https://azure.microsoft.com/en-us/pricing/details/container-apps/

[^16]: https://www.youtube.com/watch?v=JdYnVTCKYWI

[^17]: https://intercept.cloud/en-gb/blogs/aca-vs-aks-vs-aci

[^18]: https://www.linkedin.com/posts/brainboard-co_scaling-in-azure-container-apps-activity-7377097344820944896-VnSS

