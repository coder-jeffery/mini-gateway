import { AdminDashboard } from "@/components/AdminDashboard";
import { LocaleProvider } from "@/components/LocaleProvider";

export default function Home() {
  return (
    <LocaleProvider>
      <AdminDashboard />
    </LocaleProvider>
  );
}
