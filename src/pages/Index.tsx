import { useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { HardHat, ArrowRight, TrendingUp, Shield, Zap } from 'lucide-react';

export default function Index() {
  const { user, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && user) {
      navigate('/dashboard');
    }
  }, [user, loading, navigate]);

  return (
    <div className="min-h-screen blueprint-grid noise-overlay relative">
      <div className="absolute inset-0 bg-gradient-to-br from-background via-background to-card opacity-95" />

      {/* Hero Section */}
      <div className="relative z-10 container mx-auto px-4 py-20">
        {/* Logo */}
        <div className="text-center mb-16 stagger-fade-in" style={{ animationDelay: '0ms' }}>
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-primary/10 border border-primary/30 mb-6">
            <HardHat className="w-10 h-10 text-primary" />
          </div>
          <h1 className="text-5xl md:text-6xl font-heading tracking-tight mb-4">
            CONSTRUCT<span className="text-primary">LEDGER</span>
          </h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
            The Tactical Profit Engine for Construction Companies
          </p>
        </div>

        {/* Tagline */}
        <div className="text-center mb-16 stagger-fade-in" style={{ animationDelay: '100ms' }}>
          <p className="text-2xl md:text-3xl font-medium text-foreground/80 max-w-3xl mx-auto leading-relaxed">
            No guesswork. Just the granular, project-tied truth of your profit.
          </p>
        </div>

        {/* CTA */}
        <div className="text-center mb-20 stagger-fade-in" style={{ animationDelay: '150ms' }}>
          <Button
            asChild
            size="lg"
            className="tactile-press text-lg px-8 py-6 h-auto"
          >
            <Link to="/auth">
              Get Started
              <ArrowRight className="w-5 h-5 ml-2" />
            </Link>
          </Button>
          <p className="text-muted-foreground text-sm mt-4">
            Free to start • No credit card required
          </p>
        </div>

        {/* Features */}
        <div className="grid md:grid-cols-3 gap-6 max-w-4xl mx-auto">
          <div 
            className="industrial-card p-6 text-center stagger-fade-in" 
            style={{ animationDelay: '200ms' }}
          >
            <div className="w-12 h-12 rounded-lg bg-success/10 border border-success/30 flex items-center justify-center mx-auto mb-4">
              <TrendingUp className="w-6 h-6 text-success" />
            </div>
            <h3 className="font-heading text-lg mb-2">REAL-TIME P&L</h3>
            <p className="text-muted-foreground text-sm">
              See your profit margins update instantly as you log costs and income
            </p>
          </div>

          <div 
            className="industrial-card p-6 text-center stagger-fade-in" 
            style={{ animationDelay: '250ms' }}
          >
            <div className="w-12 h-12 rounded-lg bg-primary/10 border border-primary/30 flex items-center justify-center mx-auto mb-4">
              <Zap className="w-6 h-6 text-primary" />
            </div>
            <h3 className="font-heading text-lg mb-2">DEAD-SIMPLE</h3>
            <p className="text-muted-foreground text-sm">
              Log materials, labor, equipment, and subs with just a few taps
            </p>
          </div>

          <div 
            className="industrial-card p-6 text-center stagger-fade-in" 
            style={{ animationDelay: '300ms' }}
          >
            <div className="w-12 h-12 rounded-lg bg-accent/10 border border-accent/30 flex items-center justify-center mx-auto mb-4">
              <Shield className="w-6 h-6 text-accent" />
            </div>
            <h3 className="font-heading text-lg mb-2">MULTI-TENANT</h3>
            <p className="text-muted-foreground text-sm">
              Complete data isolation for your company with role-based access
            </p>
          </div>
        </div>
      </div>

      {/* Footer */}
      <footer className="relative z-10 border-t border-border py-8">
        <div className="container mx-auto px-4 text-center text-muted-foreground text-sm">
          © {new Date().getFullYear()} ConstructLedger. Built for builders.
        </div>
      </footer>
    </div>
  );
}
